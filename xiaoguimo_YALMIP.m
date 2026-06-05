% 多机场协同排序：小规模实例 MILP 精确求解 (YALMIP 建模)
clear; clc;

disp('===================================================');
disp('正在使用 YALMIP 构建并求解小规模 MILP 模型...');
disp('===================================================');

%% 1. 定义小规模场景数据 (6架飞机)
numFlights = 6;

% 目标机场: 1代表PEK, 2代表PKX
dest = [1, 1, 1, 2, 2, 2]; 

% 计划落地时间 STA (分钟)
STA = [30, 32, 36, 31, 35, 40];

% 预计到达走廊口的最早时间 (分钟)
E_gate = [10, 11, 15, 12, 14, 18];

% 各航段基准飞行时间 (分钟)
FT_gate_merge = 8 * ones(1, numFlights);
FT_merge_rwy = zeros(1, numFlights);
FT_merge_rwy(dest == 1) = 12;
FT_merge_rwy(dest == 2) = 15;

% 尾流等级 (1: Heavy, 2: Medium)
wake = [1, 2, 2, 2, 1, 2];

% 尾流间隔矩阵 S (单位: 分钟) 
S_matrix = [1.5, 2.0; 
            1.0, 1.5];

M = 10000;  % 大 M
alpha = 1.0; % 延迟惩罚权重
beta = 0.5;  % 油耗惩罚权重

%% 2. 定义 YALMIP 决策变量
% 连续时间变量 (sdpvar)
T_gate  = sdpvar(numFlights, 1);
T_merge = sdpvar(numFlights, 1);
T_rwy   = sdpvar(numFlights, 1);
Delay   = sdpvar(numFlights, 1);

% 0-1 二元排序变量 (binvar)
x_gate  = binvar(numFlights, numFlights);
x_merge = binvar(numFlights, numFlights);
x_rwy   = binvar(numFlights, numFlights);

%% 3. 构建约束条件 (Constraints)
Constraints = [];

% 3.1 变量非负与基础物理运动学约束
Constraints = [Constraints, T_gate >= E_gate'];
Constraints = [Constraints, T_merge >= T_gate + FT_gate_merge'];
Constraints = [Constraints, T_rwy >= T_merge + FT_merge_rwy'];

% 3.2 延迟时间定义 (Delay >= 实际落地 - 计划落地, 且 Delay >= 0)
Constraints = [Constraints, Delay >= T_rwy - STA'];
Constraints = [Constraints, Delay >= 0];

% 3.3 核心冲突解脱约束 (大 M 法)
for i = 1:numFlights
    for j = (i+1):numFlights
        
        % [走廊口容量约束]：同门进入间隔 >= 2 分钟
        Constraints = [Constraints, T_gate(j) - T_gate(i) >= 2 - M * (1 - x_gate(i,j))];
        Constraints = [Constraints, T_gate(i) - T_gate(j) >= 2 - M * x_gate(i,j)];
        
        % [合流点雷达间隔]：过点间隔 >= 3 分钟
        Constraints = [Constraints, T_merge(j) - T_merge(i) >= 3 - M * (1 - x_merge(i,j))];
        Constraints = [Constraints, T_merge(i) - T_merge(j) >= 3 - M * x_merge(i,j)];
        
        % [跑道尾流间隔 & 进近段防超车(FIFO)]：仅限同一机场
        if dest(i) == dest(j)
            S_ij = S_matrix(wake(i), wake(j));
            S_ji = S_matrix(wake(j), wake(i));
            
            % 尾流约束
            Constraints = [Constraints, T_rwy(j) - T_rwy(i) >= S_ij - M * (1 - x_rwy(i,j))];
            Constraints = [Constraints, T_rwy(i) - T_rwy(j) >= S_ji - M * x_rwy(i,j)];
            
            % 过了合流点严禁超车 (顺序必须一致)
            Constraints = [Constraints, x_merge(i,j) == x_rwy(i,j)];
        end
    end
end

%% 4. 定义目标函数
Objective = alpha * sum(Delay) + beta * sum(T_rwy - T_gate);

%% 5. 配置并调用求解器
% 明确指定使用 MATLAB 自带的 intlinprog 作为底层求解器
options = sdpsettings('solver', 'intlinprog', 'verbose', 1);

% 执行求解
sol = optimize(Constraints, Objective, options);

%% 6. 结果输出与打印
if sol.problem == 0
    disp('===================================================');
    disp('✅ YALMIP 求解成功！找到全局最优排班解。');
    fprintf('最优目标函数值 Z = %.2f\n', value(Objective));
    disp('===================================================');
    
    % 提取数值结果 (使用 YALMIP 的 value 函数)
    t_g_val = round(value(T_gate), 2);
    t_m_val = round(value(T_merge), 2);
    t_r_val = round(value(T_rwy), 2);
    d_val   = round(value(Delay), 2);
    
    ResultTable = table((1:numFlights)', dest', wake', STA', E_gate', ...
        t_g_val, t_m_val, t_r_val, d_val, ...
        'VariableNames', {'航班号', '目标(1PEK,2PKX)', '尾流', '计划STA', '预计到门', '实际过门', '过合流点', '实际落地', '延迟时间'});
    
    ResultTable = sortrows(ResultTable, '实际落地');
    disp(ResultTable);
else
    disp('❌ 求解失败！');
    disp(sol.info);
end