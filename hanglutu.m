% 华北四场进场协同排序：抽象拓扑网络 (包含边界、SJW与机场终点)
clear; clc; close all;

%% 1. 终端区边界数据定义 (eAIP ENR 2.1.5)
lon_dms = [
    116, 25, 09;  116, 33, 07;  116, 34, 00;  117, 16, 55;
    117, 08, 43;  117, 18, 47;  117, 30, 01;  118, 02, 04;
    118, 01, 45;  115, 31, 53;  115, 26, 10;  115, 31, 50;
    116, 25, 09
];
lat_dms = [
    40, 25, 26;  40, 36, 10;  40, 46, 40;  40, 42, 50;
    40, 21, 02;  39, 25, 36;  39, 09, 17;  39, 04, 13;
    38, 35, 29;  38, 40, 03;  39, 40, 00;  40, 26, 00;
    40, 25, 26
];
bnd_lon = lon_dms(:,1) + lon_dms(:,2)/60 + lon_dms(:,3)/3600;
bnd_lat = lat_dms(:,1) + lat_dms(:,2)/60 + lat_dms(:,3)/3600;

%% 2. 核心抽象节点定义 (走廊口 + 共用合流点 + IAF + 机场)
% 注: 坐标已使用真实数据 (度分秒转十进制) 进行人工校准映射
nodes_info = {
    % === 走廊口 (Gates) ===
    'GUVBA', 'Gate', 40.4333, 115.5306;  'BUMDU', 'Gate', 40.7139, 117.2819;
    'OSUBA', 'Gate', 40.7364, 117.0372;  'DUMAP', 'Gate', 38.5914, 118.0292;
    'AVBOX', 'Gate', 38.6478, 116.3781;  'DUGEB', 'Gate', 38.6619, 115.8039;
    'BELAX', 'Gate', 38.7200, 115.5264;  'ELAPU', 'Gate', 40.2092, 115.5028;
    'OMDEK', 'Gate', 38.6550, 116.0908;
    'VADKA', 'Gate', 39.0683, 114.3994;  'IDGIS', 'Gate', 38.7589, 114.9778;
    'TONOV', 'Gate', 38.1889, 114.1067;  'AVLIS', 'Gate', 37.4967, 115.1536;
    'LIKTI', 'Gate', 37.9622, 115.4378;
    
    % === 合流点 (Merge) ===
    'AA166', 'Merge', 40.4197, 116.6792; 'AA146', 'Merge', 39.0332, 117.1796;
    'AA142', 'Merge', 40.0381, 116.7383;
    'AD543', 'Merge', 39.0370, 116.7316; 'AD523', 'Merge', 39.3332, 116.6868;
    'TJ869', 'Merge', 40.4136, 117.0148; 'TJ862', 'Merge', 38.6540, 117.8529;
    'REVSI', 'Merge', 38.6239, 114.5997; 'PINAP', 'Merge', 38.4322, 114.7481;
    'ALBOD', 'Merge', 38.0861, 115.3011; 'VEMOT', 'Merge', 38.1261, 114.8208;
    
    % === 进近终点 (IAF) ===
    'AA141', 'IAF',   39.6860, 116.7924; 'AA123', 'IAF',   39.6467, 116.3710;
    'AA122', 'IAF',   39.4788, 116.4529;
    'AD521', 'IAF',   39.1214, 116.6024; 'AD561', 'IAF',   39.0801, 116.1694;
    'TJ841', 'IAF',   38.7083, 117.6985; 'TJ821', 'IAF',   38.7500, 117.4528;
    'WUJI',  'IAF',   38.2483, 114.8883; 'ZHENGDING','IAF',38.2800, 114.6983;
    
    % === 机场终点 (Airports) ===
    'PEK',   'Airport', 40.0733, 116.5983; 
    'PKX',   'Airport', 39.5000, 116.4000;
    'TSN',   'Airport', 39.1233, 117.3450;
    'SJW',   'Airport', 38.2817, 114.6983;
};
NodesTable = cell2table(nodes_info, 'VariableNames', {'Name', 'Type', 'Lat', 'Lon'});

%% 3. 有向边定义 (包含 IAF 到 机场 的连接)
edges_info = {
    % === PEK ===
    'OSUBA', 'AA166';  'GUVBA', 'AA166';  'AA166', 'AA142';
    'DUMAP', 'AA146';  'AVBOX', 'AA146';  'AA146', 'AA142';
    'AA142', 'AA141';  'AA141', 'PEK';    % 修复：IAF 连到机场
    'GUVBA', 'AA123';  'AA123', 'PEK';
    'AVBOX', 'AA122';  'DUGEB', 'AA122';  'AA122', 'PEK';
    
    % === PKX ===
    'BUMDU', 'AD523';  'DUMAP', 'AD543';  'AVBOX', 'AD543';
    'AD543', 'AD523';  'AD523', 'AD521';  'AD521', 'PKX';
    'BELAX', 'AD561';  'ELAPU', 'AD561';  'AD561', 'PKX';
    
    % === TSN ===
    'GUVBA', 'TJ869';  'BUMDU', 'TJ869';  'TJ869', 'TJ862';
    'DUMAP', 'TJ862';  'TJ862', 'TJ841';  'TJ841', 'TSN';
    'OMDEK', 'AVBOX';  'AVBOX', 'TJ821';  'TJ821', 'TSN';
    
    % === SJW ===
    'VADKA', 'REVSI';  'IDGIS', 'REVSI';  'REVSI', 'PINAP';
    'TONOV', 'PINAP';  'PINAP', 'WUJI';   'WUJI', 'SJW';
    'AVLIS', 'VEMOT';  'LIKTI', 'VEMOT';  'VEMOT', 'ZHENGDING'; 'ZHENGDING', 'SJW';
    'AVLIS', 'ALBOD';  'LIKTI', 'ALBOD';  'ALBOD', 'WUJI';
};

%% 4. 构建图模型与可视化
G = digraph(edges_info(:,1), edges_info(:,2));
node_lons = zeros(numnodes(G), 1); node_lats = zeros(numnodes(G), 1);
node_types = strings(numnodes(G), 1);
for i = 1:numnodes(G)
    idx = strcmp(NodesTable.Name, G.Nodes.Name{i});
    node_lons(i) = NodesTable.Lon(idx);
    node_lats(i) = NodesTable.Lat(idx);
    node_types(i) = string(NodesTable.Type{idx});
end

% === 绘图 ===
figure('Color', 'w', 'Position', [100, 100, 1000, 800]); hold on;

% 1. 画终端区背景多边形
fill(bnd_lon, bnd_lat, [0.85 0.9 0.95], 'EdgeColor', [0.3 0.5 0.7], 'LineWidth', 2, 'FaceAlpha', 0.5);

% 2. 画边
h = plot(G, 'XData', node_lons, 'YData', node_lats);
h.LineWidth = 1.2; h.ArrowSize = 8; h.EdgeColor = [0.4 0.4 0.4]; h.NodeLabel = {};

% 3. 自定义各类型节点样式
for i = 1:numnodes(G)
    type = node_types(i);
    if type == "Gate"
        plot(node_lons(i), node_lats(i), 's', 'MarkerSize', 8, 'MarkerFaceColor', [0.2 0.7 0.3], 'MarkerEdgeColor', 'k');
        text(node_lons(i), node_lats(i)+0.04, G.Nodes.Name{i}, 'FontSize', 8, 'FontWeight', 'bold');
    elseif type == "Merge"
        plot(node_lons(i), node_lats(i), 'o', 'MarkerSize', 6, 'MarkerFaceColor', [1 0.5 0], 'MarkerEdgeColor', 'k');
        text(node_lons(i)+0.02, node_lats(i), G.Nodes.Name{i}, 'Color', [0.6 0 0], 'FontSize', 8);
    elseif type == "IAF"
        plot(node_lons(i), node_lats(i), 'p', 'MarkerSize', 10, 'MarkerFaceColor', [0.3 0.6 1], 'MarkerEdgeColor', 'w');
        text(node_lons(i), node_lats(i)-0.04, G.Nodes.Name{i}, 'FontWeight', 'bold', 'Color', [0.2 0.4 0.8], 'FontSize', 8);
    elseif type == "Airport"
        % 重点突出机场
        plot(node_lons(i), node_lats(i), 'h', 'MarkerSize', 16, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
        text(node_lons(i), node_lats(i)-0.06, G.Nodes.Name{i}, 'FontWeight', 'bold', 'Color', 'r', 'FontSize', 12, 'HorizontalAlignment', 'center');
    end
end

title('华北四场协同进场：抽象拓扑网络与空域边界', 'FontSize', 15, 'FontWeight', 'bold');
xlabel('经度'); ylabel('纬度'); grid on; axis equal; set(gca, 'FontSize', 11);
% --- 修复后的图例生成代码 ---
% 1. 创建用于图例的虚拟图形句柄 (不在图上实际显示数据，只显示样式)
h1 = plot(NaN, NaN, 's', 'MarkerSize', 8, 'MarkerFaceColor', [0.2 0.7 0.3], 'MarkerEdgeColor', 'k');
h2 = plot(NaN, NaN, 'o', 'MarkerSize', 6, 'MarkerFaceColor', [1 0.5 0], 'MarkerEdgeColor', 'k');
h3 = plot(NaN, NaN, 'p', 'MarkerSize', 10, 'MarkerFaceColor', [0.3 0.6 1], 'MarkerEdgeColor', 'w');
h4 = plot(NaN, NaN, 'h', 'MarkerSize', 14, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'k');

% 2. 将句柄打包成数组，传入说明文字
legend([h1, h2, h3, h4], ...
    {'走廊口 (容量约束)', '共用合流点 (雷达间隔)', '进近终点 (IAF队列)', '机场跑道 (尾流间隔)'}, ...
    'Location', 'best', 'FontSize', 10);