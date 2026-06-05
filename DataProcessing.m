%% 多机场协同排序问题 - 第一阶段数据预处理
clear; clc; close all;
disp('=======================================================');
disp('开始执行第一阶段：数据读取、特征提取与航班池生成');
disp('=======================================================');

%% -------------------------------------------------------------
% 第一部分：解析 OpenSky 字典，提取全球机型映射表
% -------------------------------------------------------------
disp('[1/4] 正在加载 OpenSky 数据库并构建机型字典...');
db_opts = detectImportOptions('aircraftDatabase.csv');
db_opts.DataLines = [1 Inf]; 
db_opts.VariableNamesLine = 0; % 无表头模式
db_opts = setvartype(db_opts, 'string'); % 强制全字符串读取

try
    T_db = readtable('aircraftDatabase.csv', db_opts);
    % 提取第 1 列 (HexID) 和 第 6 列 (机型)
    OpenSkyDict = table(upper(strtrim(T_db.Var1)), upper(strtrim(T_db.Var6)), ...
        'VariableNames', {'HexID', 'AircraftType'});
    
    % 清洗与去重
    OpenSkyDict(OpenSkyDict.HexID == "" | OpenSkyDict.AircraftType == "", :) = [];
    [~, uniqueIdx] = unique(OpenSkyDict.HexID, 'stable');
    OpenSkyDict = OpenSkyDict(uniqueIdx, :);
    disp(['=> 成功构建机型字典，包含 ', num2str(height(OpenSkyDict)), ' 架飞机的信息。']);
catch
    error('读取 aircraftDatabase.csv 失败，请检查文件是否存在且格式正确！');
end

%% -------------------------------------------------------------
% 第二部分：高速读取 ADS-B，提取进近速度与 ROT
% -------------------------------------------------------------
disp('[2/4] 正在使用矩阵化高速模式读取 2019 年 ADS-B 数据...');
filename_adsb = '20190422-001903.csv';
T_raw = readtable(filename_adsb, 'ReadVariableNames', false, 'Delimiter', ' ');
dataStrings = string(T_raw.Var3);

% 过滤脏数据并拆分
validIdx = (count(dataStrings, ',') == 8);
T_raw = T_raw(validIdx, :);
dataStrings = dataStrings(validIdx);
payload = split(dataStrings, ',');

T_adsb = table(payload(:,1), payload(:,2), ...
    str2double(payload(:,3)), str2double(payload(:,4)), ...
    str2double(payload(:,5)), str2double(payload(:,6)), ...
    str2double(payload(:,7)), str2double(payload(:,9)), ...
    'VariableNames', {'HexID', 'Callsign', 'Lon', 'Lat', 'Alt', 'Speed', 'Heading', 'VertRate'});
T_adsb.Timestamp = datetime(string(T_raw.Var1) + " " + string(T_raw.Var2), 'InputFormat', 'yyyy-MM-dd HH:mm:ss:');

% 【关键净化】：去除 HexID 里可能夹带的单引号，并转为大写
T_adsb.HexID = upper(strrep(T_adsb.HexID, "'", ""));
T_adsb.Callsign = strtrim(string(T_adsb.Callsign));

% 提取特征
allCallsigns = unique(T_adsb.Callsign);
allCallsigns(allCallsigns == "" | startsWith(allCallsigns, "*")) = [];

disp(['=> ADS-B 读取完成，开始计算 ', num2str(length(allCallsigns)), ' 个航班的飞行特征...']);
results = table('Size', [length(allCallsigns), 4], ...
    'VariableTypes', {'string', 'string', 'double', 'double'}, ...
    'VariableNames', {'Callsign', 'HexID', 'AppSpeed', 'ROT'});

for i = 1:length(allCallsigns)
    flightID = allCallsigns(i);
    traj = sortrows(T_adsb(T_adsb.Callsign == flightID, :), 'Timestamp');
    
    results.Callsign(i) = flightID;
    results.HexID(i) = traj.HexID(1); % 记录该航班的 HexID 用于查字典
    results.AppSpeed(i) = NaN;
    results.ROT(i) = NaN;
    
    % 提取进近速度 (500m - 4000m)
    appIdx = traj.Alt >= 500 & traj.Alt <= 4000;
    if any(appIdx)
        results.AppSpeed(i) = mean(traj.Speed(appIdx), 'omitnan');
    end
    
    % 提取 ROT
    minAlt = min(traj.Alt);
    if minAlt < 1000
        groundIdx = find(traj.Alt <= minAlt + 200); 
        if ~isempty(groundIdx)
            t_in = traj.Timestamp(groundIdx(1));
            trajAfterTouchdown = traj(groundIdx(1):end, :);
            exitIdx = find(trajAfterTouchdown.Speed < 100, 1);
            if isempty(exitIdx) && height(trajAfterTouchdown) > 1
                if trajAfterTouchdown.Speed(end) < trajAfterTouchdown.Speed(1) * 0.7
                    exitIdx = height(trajAfterTouchdown);
                end
            end
            if ~isempty(exitIdx)
                rot = seconds(trajAfterTouchdown.Timestamp(exitIdx) - t_in);
                if rot >= 10 && rot <= 180 
                    results.ROT(i) = rot;
                end
            end
        end
    end
end
% 剔除全空的行
results(isnan(results.AppSpeed) & isnan(results.ROT), :) = [];

%% -------------------------------------------------------------
% 第三部分：数据融合、机型统计与尾流等级降维 (安全变量名版)
% -------------------------------------------------------------
disp('[3/4] 正在关联 OpenSky 字典，并进行双层统计分析...');

% 1. 与 OpenSky 字典进行 Join
final_results = innerjoin(results, OpenSkyDict, 'Keys', 'HexID');

% =============================================================
% 【输出表 1】：按“具体机型”统计 (保留用于大作业报告展示)
% =============================================================
finalParams = groupsummary(final_results, 'AircraftType', 'mean', {'AppSpeed', 'ROT'});
finalParams = finalParams(:, {'AircraftType', 'GroupCount', 'mean_AppSpeed', 'mean_ROT'});
% 为了后续可能的数据调用，保持英文列名，仅在展示时说明
% VariableNames: {'AircraftType', 'GroupCount', 'mean_AppSpeed', 'mean_ROT'}

disp('=> [报表1] 按【具体机型】统计的先验参数表 (可放入报告)：');
disp(head(finalParams, 8)); 

% =============================================================
% 【输出表 2】：按“尾流等级”聚合 (用于第二阶段排班模型输入)
% =============================================================
% 定义尾流等级映射规则
light_ac   = {'CL85', 'CRJ9', 'E195', 'G550'};
medium_ac  = {'A319', 'A320', 'A321', 'B737', 'B738', 'B739'};
heavy_ac   = {'A332', 'A333', 'A359', 'A388', 'B744', 'B748', 'B763', 'B772', 'B77L', 'B77W', 'B789'};

% 初始化并打上尾流标签
WakeCategory = strings(height(final_results), 1);
WakeCategory(:) = "Unknown"; 

for i = 1:height(final_results)
    ac = final_results.AircraftType(i);
    if ismember(ac, light_ac)
        WakeCategory(i) = "Light";
    elseif ismember(ac, medium_ac)
        WakeCategory(i) = "Medium";
    elseif ismember(ac, heavy_ac)
        WakeCategory(i) = "Heavy";
    end
end

% 将尾流分类写入原始明细表，并剔除未知机型
final_results.WakeCategory = WakeCategory;
final_results(final_results.WakeCategory == "Unknown", :) = [];

% 按尾流等级 (WakeCategory) 进行分组聚合
WakeParams = groupsummary(final_results, 'WakeCategory', 'mean', {'AppSpeed', 'ROT'});
WakeParams = WakeParams(:, {'WakeCategory', 'GroupCount', 'mean_AppSpeed', 'mean_ROT'});
% 重命名列为标准英文，避免 dot-indexing 报错
WakeParams.Properties.VariableNames = {'WakeCategory', 'ValidSamples', 'MeanAppSpeed', 'ExtractedROT'};

% 引入行业经验值填补 ROT 的缺失
standard_ROT = containers.Map({'Heavy', 'Medium', 'Light'}, [55, 50, 45]);
FinalROT = NaN(height(WakeParams), 1); % 纯英文变量名

for i = 1:height(WakeParams)
    cat = char(WakeParams.WakeCategory(i));
    calc_rot = WakeParams.ExtractedROT(i);
    FinalROT(i) = standard_ROT(cat);
end
% 将最终 ROT 拼接入表
WakeParams.FinalModelROT = FinalROT;

% -------------------------------------------------------------
% 纯展示环节：生成带中文表头的克隆表，仅供控制台打印查看
% -------------------------------------------------------------
DisplayTable = WakeParams;
DisplayTable.Properties.VariableNames = {'尾流等级', '有效样本数', '平均进近速度', '提取的平均ROT', '最终模型用ROT(秒)'};

disp('=> [报表2] 华北空域【尾流等级】参数表 (MILP模型输入常量)：');
disp(DisplayTable);

%% -------------------------------------------------------------
% 第四部分：解析 2025 年时刻表，生成进港航班池
% -------------------------------------------------------------
disp('[4/4] 正在解析 2025 年时刻表文件...');
filenames_schedule = {'PEK_4_4_25_JobId3280608.csv', 'PKX_4_4_25_JobId3280607.csv', ...
                      'SJW_4_4_25_JobId3280610.csv', 'TSN_4_4_25_JobId3280611.csv'};
targetAirports = {'PEK', 'PKX', 'SJW', 'TSN'};
Demand_2025 = table();

for i = 1:length(filenames_schedule)
    fname = filenames_schedule{i};
    opts = detectImportOptions(fname);
    opts.DataLines = [24 Inf]; 
    opts.VariableNamesLine = 23; 
    
    allVars = opts.VariableNames; 
    opts = setvartype(opts, allVars, 'string'); % 全转字符串，避免表头识别错误
    
    try
        T_current = readtable(fname, opts);
        actualNames = T_current.Properties.VariableNames;
        
        destCol = actualNames{contains(actualNames, 'Destination', 'IgnoreCase', true)};
        flightCol = actualNames{contains(actualNames, 'Flight', 'IgnoreCase', true)};
        carrierCol = actualNames{contains(actualNames, 'Carrier', 'IgnoreCase', true)};
        timeCol = actualNames{contains(actualNames, 'Arrival', 'IgnoreCase', true)};
        equipCol = actualNames{contains(actualNames, 'Equipment', 'IgnoreCase', true)};
        
        % 筛选进港航班
        isArrival = ismember(T_current.(destCol), targetAirports);
        T_arrival = T_current(isArrival, :);
        
        % 组装临时表
        tempPool = table();
        tempPool.Callsign = T_arrival.(carrierCol) + T_arrival.(flightCol);
        tempPool.AircraftType = T_arrival.(equipCol);
        tempPool.Dest = T_arrival.(destCol);
        tempPool.STA_String = strtrim(T_arrival.(timeCol));
        
        Demand_2025 = [Demand_2025; tempPool];
    catch
        fprintf('警告：读取或解析文件 %s 失败，请检查文件存在。\n', fname);
    end
end

% --- 安全计算分钟数 (防弹设计) ---
STA_Minutes = NaN(height(Demand_2025), 1);
for k = 1:height(Demand_2025)
    s = Demand_2025.STA_String(k);
    if s == "" || ismissing(s)
        continue;
    end
    if contains(s, ':')
        parts = split(s, ':');
        STA_Minutes(k) = str2double(parts(1))*60 + str2double(parts(2));
    elseif strlength(s) == 4 % 处理类似 '1430' 格式
        h = str2double(extractBefore(s, 3));
        m = str2double(extractAfter(s, 2));
        STA_Minutes(k) = h*60 + m;
    end
end
Demand_2025.STA_Min = STA_Minutes;

% 剔除无效时间行并排序
Demand_2025(isnan(Demand_2025.STA_Min), :) = [];
Demand_2025 = sortrows(Demand_2025, 'STA_Min');

disp('=======================================================');
disp('第一阶段大功告成！2025年协同排序航班池构建完毕。');
disp(['共提取出有效进港航班：', num2str(height(Demand_2025)), ' 架次。']);
disp('前 5 架到达的航班预览：');
disp(head(Demand_2025, 5));


