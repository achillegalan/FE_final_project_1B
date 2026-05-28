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

% Plot: OIS discount curve 2022 vs 2023 (MA ANCHE DA TOGLIERE)
% tau22 = yearfrac(settlementDate, OIS_Boot.dates, 3);
% tau23 = yearfrac(settlementDate_2, OIS_Boot_2.dates, 3);

% figure;
% plot(tau22, OIS_Boot.discounts, '-o', 'LineWidth', 1.3, 'DisplayName', 'OIS 2022');
% hold on;
% plot(tau23, OIS_Boot_2.discounts, '-s', 'LineWidth', 1.3, 'DisplayName', 'OIS 2023');
% grid on;
% xlabel('Maturity (years)');
% ylabel('Discount Factor');
% title('OIS Discount Curves: 2022 vs 2023');
% legend('Location','best');

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

% Scenario 1: CDS Spread = 300 bps
cdsSpreads_300 = 0.03; 
[CVA_300, survProbs_300] = computeCVA( ...
    swapData,OIS_Boot, EUR3M_Boot, settlementDate, strike, normalVol, ...
    isPayer, fixingFrequency, cdsSpreads_300, LGD);
[CVA_300_cost, survProbs_300_cost] = computeCVAConstantLambda( ...
     swapData,OIS_Boot, EUR3M_Boot, settlementDate, strike, normalVol, ...
     isPayer, fixingFrequency, cdsSpreads_300, LGD);    
% Scenario 2: CDS Spread = 500 bps
cdsSpreads_500 = 0.05; 
[CVA_500, survProbs_500] = computeCVA( ...
    swapData,OIS_Boot, EUR3M_Boot, settlementDate, strike, normalVol, ...
    isPayer, fixingFrequency, cdsSpreads_500, LGD);
[CVA_500_cost, survProbs_500_cost] = computeCVAConstantLambda( ...
     swapData,OIS_Boot, EUR3M_Boot, settlementDate, strike, normalVol, ...
     isPayer, fixingFrequency, cdsSpreads_500, LGD);    
NPV_300 = swap_quarterly - CVA_300;
NPV_500 = swap_quarterly - CVA_500;

fprintf("CVA (CDS = 300 bps)          : %.2f EUR\n", CVA_300);
fprintf("CVA cost (CDS = 300 bps)     : %.2f EUR\n", CVA_300_cost);
fprintf("Swap NPV with CVA (300 bps)  : %.2f EUR\n", NPV_300);
fprintf("CVA (CDS = 500 bps)          : %.2f EUR\n", CVA_500);
fprintf("CVA cost (CDS = 500 bps)     : %.2f EUR\n", CVA_500_cost);
fprintf("Swap NPV with CVA (500 bps)  : %.2f EUR\n\n", NPV_500);

%% TASK 4: CVA 2023
fprintf('\n\n========= Task 4: CVA Computation 2023 =========\n')
% the rate is taken by ...
knownFixing = struct('resetStartDate', datetime(2022,12,28), 'resetRate', 0.02202);

swap_unwind_quarterly = AmmortizedSwapPricer( ...
    swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, 'quarterly', knownFixing);
swap_unwind_semiannual = AmmortizedSwapPricer( ...
    swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, 'semiannual', knownFixing);
fprintf("Swap price from Bank perspective (MtM) [reset: quarterly] is: %.2f EUR\n", swap_unwind_quarterly);
fprintf("Swap price from Bank perspective (MtM) [reset: semiannual] is: %.2f EUR\n", swap_unwind_semiannual);

normalVol_2=loadSwaptionVolsUnwinding();
% Unwinding CVA at 300 bps
[CVA_unwind_300,survProbs_300, CVA_det_300, CVA_stoch_300] = computeCVA( ...
     swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, ...
     normalVol_2, isPayer, 'quarterly', cdsSpreads_300, LGD,knownFixing);

% Unwinding CVA at 500 bps
[CVA_unwind_500, survProbs_500, CVA_det_500, CVA_stoch_500] = computeCVA( ...
     swapData, OIS_Boot_2, EUR3M_Boot_2, settlementDate_2, fixedRate, ...
     normalVol_2, isPayer, 'quarterly', cdsSpreads_500, LGD,knownFixing);
fprintf("Unwind CVA (CDS = 300 bps)          : %.2f EUR\n", CVA_unwind_300);
fprintf("Unwind Swap NPV with CVA (300 bps)  : %.2f EUR\n", swap_unwind_quarterly - CVA_unwind_300);

fprintf("Unwind CVA (CDS = 500 bps)          : %.2f EUR\n", CVA_unwind_500);
fprintf("Unwind Swap NPV with CVA (500 bps)  : %.2f EUR\n", swap_unwind_quarterly - CVA_unwind_500);

%% TASK 5: Calibration
fprintf('\n\n========= Task 5: Calibration Multicurve Swaption model =========\n')
gammas = [0, 0.5, 1];

% Build diagonal swaption quotes directly from the full market cubes.
diagExpiry = [1; 3; 5; 8; 10; 12; 15];
diagTenor  = [15; 12; 10; 7; 5; 3; 1];
diagSwaptions2022 = buildDiagonalSwaptionTable(diagExpiry, diagTenor, "2022");
diagSwaptions2023 = buildDiagonalSwaptionTable(diagExpiry, diagTenor, "2023");

diagMkt2022 = buildDiagonalSwaptionMarketData(OIS_Boot, EUR3M_Boot, diagSwaptions2022, true);
diagMkt2023 = buildDiagonalSwaptionMarketData(OIS_Boot_2, EUR3M_Boot_2, diagSwaptions2023, true);
%disp(diagMkt2022.summary)
%disp(diagMkt2023.summary)

isPayer = true; isPD = true;
for g = gammas
    [a22, b22, cal22] = calibrateMHWabDiagonal(OIS_Boot, EUR3M_Boot, diagMkt2022, g, isPayer, isPD);
    [a23, b23, cal23] = calibrateMHWabDiagonal(OIS_Boot_2, EUR3M_Boot_2, diagMkt2023, g, isPayer, isPD);

    fprintf('\nGamma = %.2f\n', g);
    fprintf('  2022 -> a = %.8f, b = %.8f, SSE = %.6e\n ', ...
        a22, b22, cal22.sse);
    fprintf('  2023 -> a = %.8f, b = %.8f, SSE = %.6e\n', ...
        a23, b23, cal23.sse);
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
