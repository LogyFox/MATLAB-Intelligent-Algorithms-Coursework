% 多机场协同排序：遗传算法 (GA) 主程序框架
clear; clc; close all;

disp('===================================================');
disp('🚀 初始化多机场协同排序遗传算法 (GA) ...');
disp('===================================================');

%% 1. 参数设置与数据导入
% --- 算法参数 ---
pop_size = 50;        % 种群规模
max_gen = 100;        % 最大迭代代数
pc = 0.8;             % 交叉概率 (Crossover Rate)
pm = 0.1;             % 变异概率 (Mutation Rate)
alpha = 1.0; beta = 0.5; % 延迟与油耗权重

% --- 模拟航班数据 (此处可替换为你第一阶段处理好的 2025 年几百架航班的数据) ---
numFlights = 6;
dest = [1, 1, 1, 2, 2, 2]; % 1=PEK, 2=PKX
STA = [30, 32, 36, 31, 35, 40];
E_gate = [10, 11, 15, 12, 14, 18];
FT_g2m = [8, 8, 8, 8, 8, 8];
FT_m2r = [12, 12, 12, 15, 15, 15];
wake = [1, 2, 2, 2, 1, 2];
S_matrix = [1.5, 2.0; 1.0, 1.5]; % 尾流矩阵

%% 2. 初始化种群 (生成随机排列)
% pop 是一个矩阵，每一行代表一个个体(一种排班顺序)
pop = zeros(pop_size, numFlights);
for i = 1:pop_size
    pop(i, :) = randperm(numFlights);
end

% 记录历史最优
best_fitness_history = zeros(max_gen, 1);
global_best_chrom = [];
global_best_Z = inf;

%% 3. GA 主循环
disp('开始进化迭代...');
for gen = 1:max_gen
    
    % 3.1 适应度评估 (解码)
    fitness = zeros(pop_size, 1);
    Z_values = zeros(pop_size, 1);
    
    for p = 1:pop_size
        chrom = pop(p, :);
        % 调用解码函数计算目标值 Z
        Z = decode_and_evaluate(chrom, numFlights, dest, STA, E_gate, FT_g2m, FT_m2r, wake, S_matrix, alpha, beta);
        Z_values(p) = Z;
        fitness(p) = 1.0 / (Z + 1e-6); % 转换为适应度 (越大越好)
    end
    
    % 记录本代最优
    [min_Z, best_idx] = min(Z_values);
    if min_Z < global_best_Z
        global_best_Z = min_Z;
        global_best_chrom = pop(best_idx, :);
    end
    best_fitness_history(gen) = global_best_Z;
    
    % 3.2 轮盘赌选择 (Selection)
    % 也可以换成锦标赛选择 (Tournament)
    prob = fitness / sum(fitness);
    cum_prob = cumsum(prob);
    new_pop = zeros(size(pop));
    for i = 1:pop_size
        r = rand();
        idx = find(cum_prob >= r, 1, 'first');
        new_pop(i, :) = pop(idx, :);
    end
    pop = new_pop;
    
    % 3.3 顺序交叉 (Order Crossover - OX)
    for i = 1:2:(pop_size-1)
        if rand() < pc
            p1 = pop(i, :); p2 = pop(i+1, :);
            % 随机生成两个切点
            pts = sort(randperm(numFlights, 2));
            c1 = zeros(1, numFlights); c2 = zeros(1, numFlights);
            % 中间部分直接保留
            c1(pts(1):pts(2)) = p1(pts(1):pts(2));
            c2(pts(1):pts(2)) = p2(pts(1):pts(2));
            % 填补剩余部分 (保证无重复)
            c1 = fill_ox(c1, p2, pts(1), pts(2), numFlights);
            c2 = fill_ox(c2, p1, pts(1), pts(2), numFlights);
            pop(i, :) = c1; pop(i+1, :) = c2;
        end
    end
    
    % 3.4 两点交换变异 (Swap Mutation)
    for i = 1:pop_size
        if rand() < pm
            pts = randperm(numFlights, 2);
            temp = pop(i, pts(1));
            pop(i, pts(1)) = pop(i, pts(2));
            pop(i, pts(2)) = temp;
        end
    end
    
    % 精英保留策略：强制把历史最优个体塞入下一代，防止退化
    pop(1, :) = global_best_chrom;
end

%% 4. 输出结果与可视化
disp('===================================================');
fprintf('✅ GA 求解完成！最优目标函数值 Z = %.2f\n', global_best_Z);
disp('最优进场序列为:');
disp(global_best_chrom);
disp('===================================================');

% 画收敛曲线
figure('Color', 'w');
plot(1:max_gen, best_fitness_history, 'b-', 'LineWidth', 2);
title('遗传算法收敛曲线 (Genetic Algorithm Convergence)');
xlabel('迭代代数 (Generations)');
ylabel('最优目标函数值 (加权代价 Z)');
grid on;

% =========================================================================
% 以下是 GA 必需的辅助函数 (放在同一个脚本的最下方即可，MATLAB支持这种写法)
% =========================================================================

function Z = decode_and_evaluate(chrom, N, dest, STA, E_gate, FT_g2m, FT_m2r, wake, S_matrix, alpha, beta)
    % 贪婪推演算法：将染色体序列转化为实际到达时间
    T_gate = zeros(1, N);
    T_merge = zeros(1, N);
    T_rwy = zeros(1, N);
    
    % 记录各资源上一个被占用时间 (用于算间隔)
    % 简化模型：假设大家用同一个门、同一个合流点，去不同的跑道
    last_gate_time = -inf;
    last_merge_time = -inf;
    last_rwy_time = [-inf, -inf]; % 1=PEK, 2=PKX
    last_rwy_wake = [0, 0];
    
    for k = 1:N
        idx = chrom(k); % 当前轮到的航班索引
        
        % 1. 过门时间计算
        t_g = max(E_gate(idx), last_gate_time + 2);
        T_gate(idx) = t_g;
        last_gate_time = t_g;
        
        % 2. 过合流点时间计算
        t_m = max(t_g + FT_g2m(idx), last_merge_time + 3);
        T_merge(idx) = t_m;
        last_merge_time = t_m;
        
        % 3. 落地时间计算
        d = dest(idx); % 该航班去哪个机场
        if last_rwy_wake(d) == 0
            req_sep = 0; % 第一架飞机没有尾流间隔要求
        else
            req_sep = S_matrix(last_rwy_wake(d), wake(idx));
        end
        t_r = max(t_m + FT_m2r(idx), last_rwy_time(d) + req_sep);
        T_rwy(idx) = t_r;
        last_rwy_time(d) = t_r;
        last_rwy_wake(d) = wake(idx);
    end
    
    % 4. 计算目标函数 Z
    delay = max(0, T_rwy - STA);
    fuel = T_rwy - T_gate;
    Z = sum(alpha * delay + beta * fuel);
end

function child = fill_ox(child, parent, p1, p2, N)
    % 顺序交叉(OX)的填补逻辑
    idx_child = mod(p2, N) + 1;
    idx_parent = mod(p2, N) + 1;
    
    while any(child == 0)
        % 如果 parent 的这个基因还没有在 child 中
        if ~ismember(parent(idx_parent), child)
            child(idx_child) = parent(idx_parent);
            idx_child = mod(idx_child, N) + 1;
        end
        idx_parent = mod(idx_parent, N) + 1;
    end
end