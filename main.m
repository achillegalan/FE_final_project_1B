% Final Project - Group 1b
% Achille Galante, Salvatore Ippolito, Ginevra Angelica Marelli
clc
clear all
rng(1234);
ActiveFolders()

%% LOADING DATASET
% 2022
% tradeDate = datetime(2022, 6, 24);  --> usando questo come refDate, esce la stessa cosa per il settlement
% una differenza cambierà nelle yearfract leggermente (RISENTIRE COSA DICE LOCATELLI)
refDate = datetime(2022, 6, 26);
settlementDate = add_target_business_days(refDate, 2);
curveFile  = fullfile('data', '20220626_Curve.xlsx');  
curveColumns = {'Term', 'Market Rate'};
OIS_Curve = importExcellData(curveFile, 'OIS ESTR Curve', curveColumns);
EUR3M_Curve = importExcellData(curveFile, '3MCurve', curveColumns);

% 2023
refDate_2 = datetime(2023, 1, 31);
settlementDate_2 = add_target_business_days(refDate_2, 2);
curveFile_2  = fullfile('data', '20230131_Curve.xlsx');  
OIS_Curve_2   = importExcellData(curveFile_2, 'Curva OIS 31 Jan', curveColumns);
EUR3M_Curve_2 = importExcellData(curveFile_2, 'Curve 3M 31 Jan',  curveColumns);

% Swap Amortizing
swapData = importExcellData('SwapAmortizingPlan_v1.xlsx', 'SwapPlan', ...
    {'Pay Date', 'Accrual Start', 'Accrual End', 'Days', 'Notional'});

%% TASK 1: Multi-curve
% 2022 curves
OIS_Boot = bootstrapOIS(settlementDate, OIS_Curve);
EUR3M_Boot = bootstrapCrab3M(EUR3M_Curve, OIS_Boot, settlementDate, true);
% disp(EUR3M_Boot.table)

% 2023 curves
OIS_Boot_2 = bootstrapOIS(settlementDate_2, OIS_Curve_2);
EUR3M_Boot_2 = bootstrapCrab3M(EUR3M_Curve_2, OIS_Boot_2, settlementDate_2, true);
%disp(EUR3M_Boot_2.table)

%% TASK 2: NPV_riskfree Ammortized Swap
fprintf('\n\n========= Task 2: NPV risk-free 2022 =========\n')
fixedRate = 0.0221;
swap_quarterly = AmmortizedSwapPricer( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, fixedRate, 'quarterly', []);
swap_semiannual = AmmortizedSwapPricer( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, fixedRate, 'semiannual', []);
fprintf("Swap price from Bank perspective (MtM) [reset: quarterly] is: %.2f EUR\n", swap_quarterly);
fprintf("Swap price from Bank perspective (MtM) [reset: semiannual] is: %.2f EUR\n", swap_semiannual);

%% TASK 3: Amortizing Swap Pricing with CVA: simplified approach
fprintf('\n\n========= Task 3: CVA Computation 2022 =========\n')

normalVol = loadSwaptionVols();
strike = fixedRate;
% Bank receives Euribor 3M, pays 2.21%. 
% The exposure to Corporate default happens when the swap value is positive to Bank. 
% An option to enter a Pay-Fixed Swap is a Payer Swaption.
isPayer = true; 
fixingFrequency = 'quarterly';
LGD = 0.40;

scenarioBps = [300 500];
cdsSpreads  = scenarioBps/1e4;
cdsSpreads_300 = cdsSpreads(1);
cdsSpreads_500 = cdsSpreads(2);

[CVA_cell, surv_cell] = arrayfun(@(s) computeCVA( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, strike, normalVol, ...
    isPayer, fixingFrequency, s, LGD), cdsSpreads, 'UniformOutput', false);

[CVA_cost_cell, surv_cost_cell] = arrayfun(@(s) computeCVAConstantLambda( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, strike, normalVol, ...
    isPayer, fixingFrequency, s, LGD), cdsSpreads, 'UniformOutput', false);

CVA_vec      = [CVA_cell{:}];
CVA_cost_vec = [CVA_cost_cell{:}];
NPV_vec      = swap_quarterly - CVA_vec;

fprintf('\n%-10s | %-14s | %-14s | %-18s\n', ...
    'CDS (bps)', 'CVA [EUR]', 'CVA cost [EUR]', 'Swap NPV with CVA');
fprintf('%s\n', repmat('-', 1, 68));
for k = 1:numel(scenarioBps)
    fprintf('%-10d | %14.2f | %14.2f | %18.2f\n', ...
        scenarioBps(k), CVA_vec(k), CVA_cost_vec(k), NPV_vec(k));
end

%% TASK 4: CVA 2023
fprintf('\n\n========= Task 4: CVA Computation 2023 =========\n')
% the rate is taken by ...
knownFixing_2023 = struct('resetStartDate', datetime(2022,12,28), 'resetRate', 0.02202);

resetFrequencies = {'quarterly', 'semiannual'};
swapUnwindPrices = cellfun(@(f) AmmortizedSwapPricer( ...
    swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, f, knownFixing_2023), ...
    resetFrequencies);

fprintf('\n%-12s | %-16s\n', 'Reset', 'MtM [EUR]');
fprintf('%s\n', repmat('-', 1, 33));
for k = 1:numel(resetFrequencies)
    fprintf('%-12s | %16.2f\n', resetFrequencies{k}, swapUnwindPrices(k));
end

normalVol_2 = loadSwaptionVolsUnwinding();
[CVA_unwind_cell, survProbs_unwind_cell, CVA_det_cell, CVA_stoch_cell] = arrayfun(@(s) computeCVA( ...
    swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, ...
    normalVol_2, isPayer, 'quarterly', s, LGD, knownFixing_2023), ...
    cdsSpreads, 'UniformOutput', false);

CVA_unwind_vec = [CVA_unwind_cell{:}];
CVA_det_vec = [CVA_det_cell{:}];
CVA_stoch_vec = [CVA_stoch_cell{:}];
NPV_unwind_vec = swapUnwindPrices(1) - CVA_unwind_vec;

fprintf('\n%-10s | %-14s | %-14s | %-14s | %-18s\n', ...
    'CDS (bps)', 'CVA [EUR]', 'CVA_det [EUR]', 'CVA_stoch [EUR]', 'Swap NPV with CVA');
fprintf('%s\n', repmat('-', 1, 84));
for k = 1:numel(scenarioBps)
    fprintf('%-10d | %14.2f | %14.2f | %14.2f | %18.2f\n', ...
        scenarioBps(k), CVA_unwind_vec(k), CVA_det_vec(k), CVA_stoch_vec(k), NPV_unwind_vec(k));
end

%% TASK 5: Calibration
fprintf('\n\n========= Task 5: Calibration Multicurve Swaption model =========\n')
gammas = [0, 0.5, 1];

% Build diagonal swaption quotes directly from the full market cubes.
diagExpiry = [1; 3; 5; 8; 10; 12; 15];
diagTenor  = [15; 12; 10; 7; 5; 3; 1];
diagSwaptions2022 = buildDiagonalSwaptionTable(diagExpiry, diagTenor, "2022");
diagSwaptions2023 = buildDiagonalSwaptionTable(diagExpiry, diagTenor, "2023");

isPayer = true;
deliveryFlags = [true, false];  % true = Physical Delivery, false = Cash Settle

deliveryNames = {'PHYSICAL DELIVERY', 'CASH SETTLE'};
for m = 1:numel(deliveryFlags)
    isPDMode = deliveryFlags(m);
    isCSMode = ~isPDMode;  % CS convention for cash-settled, PS convention for physical-delivery

    diagMkt2022 = buildDiagonalSwaptionMarketData( ...
        OIS_Boot, EUR3M_Boot, diagSwaptions2022, isPayer, isCSMode);
    diagMkt2023 = buildDiagonalSwaptionMarketData( ...
        OIS_Boot_2, EUR3M_Boot_2, diagSwaptions2023, isPayer, isCSMode);

    [a22_c, b22_c, cal22_c] = arrayfun(@(g) calibrateMHWabDiagonal( ...
        OIS_Boot, EUR3M_Boot, diagMkt2022, g, isPayer, isPDMode), ...
        gammas, 'UniformOutput', false);
    [a23_c, b23_c, cal23_c] = arrayfun(@(g) calibrateMHWabDiagonal( ...
        OIS_Boot_2, EUR3M_Boot_2, diagMkt2023, g, isPayer, isPDMode), ...
        gammas, 'UniformOutput', false);

    marketConvLabel = 'PS';
    if isCSMode
        marketConvLabel = 'CS';
    end
    fprintf('\n%s  [market convention: %s]\n', ...
        deliveryNames{m}, marketConvLabel);
    fprintf('%-8s | %-37s | %-37s\n', 'Gamma', '2022 (a, b, SSE)', '2023 (a, b, SSE)');
    fprintf('%s\n', repmat('-', 1, 90));
    for k = 1:numel(gammas)
        fprintf('%-8.2f | a=%10.8f, b=%10.8f, SSE=%10.3e | a=%10.8f, b=%10.8f, SSE=%10.3e\n', ...
            gammas(k), a22_c{k}, b22_c{k}, cal22_c{k}.sse, a23_c{k}, b23_c{k}, cal23_c{k}.sse);
    end
end
%% Landscape della funzione obiettivo (Task 5)
% gammaPlot = 0.5;
% % passata veloce
% aVec = linspace(1e-3, 20, 50);
% bVec = linspace(1e-3, 20, 50);
% 
% [A,B,SSE,minPoint] = plotMHWabObjectiveLandscape( ...
%     OIS_Boot, EUR3M_Boot, diagMkt2022, 0.5, true, aVec, bVec);

%fprintf('Grid min: a=%.6f, b=%.6f, SSE=%.6e\n', ...
    %minPoint.a, minPoint.b, minPoint.sse);

%% TASK 6: CVA with tree
fprintf('\n\n========= Task 6: Amortizing Swap Pricing with CVA with numerical technique =========\n')
hw.a=0.001;
hw.sigma=0.01;
[NPV_riskfree, CVA, final_price] = price_amortizing_swap_cva_hw(hw,...
     swapData, OIS_Boot, EUR3M_Boot, settlementDate, fixedRate, ...
     isPayer, 'quarterly', cdsSpreads_300, LGD);
fprintf("NPV_riskfree 2022: %.2f EUR\n",NPV_riskfree);
fprintf("CVA 2022: %.2f EUR\n",CVA);
fprintf("NPV 2022: %.2f EUR\n",final_price);

knownFixing = struct('resetStartDate', datetime(2022,12,28), 'resetRate', 0.02202);  
[NPV_riskfree, CVA, final_price] = price_amortizing_swap_cva_hw(hw,...
     swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, ...
     isPayer, 'quarterly', cdsSpreads_300, LGD,knownFixing);
fprintf("NPV_riskfree 2023: %.2f EUR\n",NPV_riskfree);
fprintf("CVA 2023: %.2f EUR\n",CVA);
fprintf("NPV 2023: %.2f EUR\n",final_price);
