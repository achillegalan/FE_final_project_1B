%% Pricing in a Multi-Curve Framework
% Final Project - Group 1b
% Achille Galante, Salvatore Ippolito, Ginevra Angelica Marelli
clc
clear all
tic
rng(1234);
ActiveFolders()

%% LOADING DATASET
% 2022
refDate = datetime(2022, 6, 24);
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
knownFixing_2022 = struct('fixingDate', datetime(2022,06,24), 'resetRate', -0.00218);
fixedRate = 0.0221;
swap_quarterly = AmmortizedSwapPricer( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, fixedRate, 'quarterly', knownFixing_2022);
swap_semiannual = AmmortizedSwapPricer( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, fixedRate, 'semiannual', knownFixing_2022);
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

cdsSpreads = [300 500]/1e4;

hazardModes = ["bootstrap", "constant_lambda"];
hazardNames = ["BOOTSTRAP", "CONSTANT LAMBDA"];

[CVA_2022, CVA_det_2022, CVA_stoch_2022, NPV_2022] = runCVASection( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, strike, normalVol, ...
    isPayer, fixingFrequency, cdsSpreads, LGD, knownFixing_2022, ...
    hazardModes, swap_quarterly);

printCVATable('2022', swap_quarterly, cdsSpreads, hazardNames, ...
    CVA_2022, CVA_det_2022, CVA_stoch_2022, NPV_2022);

%% TASK 4: CVA 2023
fprintf('\n\n========= Task 4: CVA Computation 2023 =========\n')

knownFixing_2023 = struct('fixingDate', datetime(2022,12,23), 'resetRate', 0.02141);

% MtM risk-free quarterly
swapUnwindPrice = AmmortizedSwapPricer( ...
    swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, ...
    fixingFrequency, knownFixing_2023);

normalVol_2 = loadSwaptionVolsUnwinding();

[CVA_2023, CVA_det_2023, CVA_stoch_2023, NPV_2023] = runCVASection( ...
    swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, normalVol_2, ...
    isPayer, fixingFrequency, cdsSpreads, LGD, knownFixing_2023, ...
    hazardModes, swapUnwindPrice);

printCVATable('2023', swapUnwindPrice, cdsSpreads, hazardNames, ...
    CVA_2023, CVA_det_2023, CVA_stoch_2023, NPV_2023);

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
    isCSMode = ~isPDMode; 
    
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
        
    % --- NUOVO: Salvataggio specifico dei parametri Physical Delivery per il Task 6 ---
    if isPDMode
        % Salviamo i parametri per gamma = 0 (indice 1)
        hw_PD_2022.a = a22_c{1};
        hw_PD_2022.sigma = b22_c{1};
        
        hw_PD_2023.a = a23_c{1};
        hw_PD_2023.sigma = b23_c{1};
    end
    % ----------------------------------------------------------------------------------

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

frequencies = {'quarterly', 'semiannual'};

% ==========================================
% 2022
% ==========================================
fprintf('\n--- REFERENCE DATE: 2022 ---\n');
fprintf('Parametri HW (Physical Delivery, gamma=0) estratti dal Task 5 (2022): a = %.8f, sigma (b) = %.8f\n\n', hw_PD_2022.a, hw_PD_2022.sigma);

for i = 1:length(frequencies)
    freq = frequencies{i};
    for j = 1:length(cdsSpreads)
        cds = cdsSpreads(j);
        
        [NPV_riskfree, CVA, final_price] = price_amortizing_swap_cva_hw(hw_PD_2022,...
             swapData, OIS_Boot, EUR3M_Boot, settlementDate, fixedRate, ...
             isPayer, freq, cds, LGD);
             
        fprintf("Freq: %-10s | CDS: %3d bps | NPV_riskfree: %10.2f EUR | CVA: %10.2f EUR | Final NPV: %10.2f EUR\n", ...
            freq, round(cds*10000), NPV_riskfree, CVA, final_price);
    end
end

% ==========================================
% 2023
% ==========================================
fprintf('\n--- REFERENCE DATE: 2023 ---\n');
fprintf('Parametri HW (Physical Delivery, gamma=0) estratti dal Task 5 (2023): a = %.8f, sigma (b) = %.8f\n\n', hw_PD_2023.a, hw_PD_2023.sigma);

for i = 1:length(frequencies)
    freq = frequencies{i};
    for j = 1:length(cdsSpreads)
        cds = cdsSpreads(j);
        
        [NPV_riskfree, CVA, final_price] = price_amortizing_swap_cva_hw(hw_PD_2023,...
             swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, ...
             isPayer, freq, cds, LGD, knownFixing_2023);
             
        fprintf("Freq: %-10s | CDS: %3d bps | NPV_riskfree: %10.2f EUR | CVA: %10.2f EUR | Final NPV: %10.2f EUR\n", ...
            freq, round(cds*10000), NPV_riskfree, CVA, final_price);
    end
end
