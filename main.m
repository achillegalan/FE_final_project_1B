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

% 2023 curves
OIS_Boot_2 = bootstrapOIS(settlementDate_2, OIS_Curve_2);
EUR3M_Boot_2 = bootstrapCrab3M(EUR3M_Curve_2, OIS_Boot_2, settlementDate_2, true);

%% TASK 2: NPV_riskfree Ammortized Swap
fprintf('\n========= Task 2: NPV risk-free 2022 =========\n')
knownFixing_2022 = struct('fixingDate', datetime(2022,06,24), 'resetRate', -0.00218);
fixedRate = 0.0221;
swap_quarterly = AmmortizedSwapPricer( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, fixedRate, 'quarterly', knownFixing_2022);
swap_semiannual = AmmortizedSwapPricer( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, fixedRate, 'semiannual', knownFixing_2022);
fprintf("Swap price from Bank perspective (MtM) [reset: quarterly] is:  %.2f EUR\n", swap_quarterly);
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

%% TASK 5: MHW calibration (CS only)
fprintf('\n\n========= Task 5: Calibration MHW =========\n');
gammas = [0, 0.5, 1];
isPayer = true;
isCS = true;    % true  -> CS convention in market data builder

diagExpiry = [1; 3; 5; 8; 10; 12; 15];
diagTenor  = [15; 12; 10; 7; 5; 3; 1];

yearLabels = ["2022","2023"];
OISBoots   = {OIS_Boot, OIS_Boot_2};
EURBoots   = {EUR3M_Boot, EUR3M_Boot_2};

% Build diagonal quotes and market calibration data once per year.
diagSwaptions2022 = buildDiagonalSwaptionTable(diagExpiry, diagTenor, "2022");
diagSwaptions2023 = buildDiagonalSwaptionTable(diagExpiry, diagTenor, "2023");
diagSwaptions = {diagSwaptions2022, diagSwaptions2023};

diagMkt2022 = buildDiagonalSwaptionMarketData(OIS_Boot,   EUR3M_Boot,   diagSwaptions2022, isPayer, isCS);
diagMkt2023 = buildDiagonalSwaptionMarketData(OIS_Boot_2, EUR3M_Boot_2, diagSwaptions2023, isPayer, isCS);
diagMkt = {diagMkt2022, diagMkt2023};

        % %% 1. OBJECTIVE LANDSCAPE PLOT (only gamma = 0, year = 2022)
        % aVec = linspace(0.0001, 0.15, 30);
        % bVec = linspace(0.0020, 0.0200, 30);
        %
        % [~, ~, ~, minPoint] = plotMHWabObjectiveLandscape( ...
        %    OISBoots{1}, EURBoots{1}, diagMkt{1}, 0, isPayer, aVec, bVec, isCS);
        %
        % %% 2. HYBRID CALIBRATION (all 6 cases: 3 gammas x 2 years)
        % years = [2022, 2023];
        % [hybridTableCS, hybridResCS] = runCalibrationHybrid( ...
        %     years, gammas, OISBoots, EURBoots, diagMkt, isPayer, isCS);

%% 3. LOCAL CALIBRATION (all 6 cases: 3 gammas x 2 years)
a = zeros(2, numel(gammas));
b = zeros(2, numel(gammas));
sse = zeros(2, numel(gammas));
rmse = zeros(2, numel(gammas));   

for y = 1:numel(OISBoots)
    [aC, bC, calC] = arrayfun(@(g) calibrateMHWabDiagonal( ...
        OISBoots{y}, EURBoots{y}, diagMkt{y}, g, isPayer, isCS), ...
        gammas, 'UniformOutput', false);

    a(y,:) = cell2mat(aC);
    b(y,:) = cell2mat(bC);
    sse(y,:) = cellfun(@(c) c.sse, calC);
    rmse(y,:) = cellfun(@(c) c.rmse, calC);  
end

calibTableCS = table( repelem([2022; 2023], numel(gammas)), ...
    repmat(gammas(:), 2, 1), reshape(a.', [], 1), reshape(b.', [], 1), ...
    reshape(sse.', [], 1), reshape(rmse.', [], 1), ...
    'VariableNames', {'Year','Gamma','a','b','SSE','RMSE'});

fprintf('\nLocal calibration summary:\n');
disp(calibTableCS);

%% TASK 6: CVA with tree
fprintf('\n\n========= Task 6: Amortizing Swap Pricing with CVA with numerical technique =========\n')

% Estract the values of a and gamma from the previous point
calibGamma0 = calibTableCS(calibTableCS.Gamma == 0, :);
hw_CS_2022 = struct('a', calibGamma0.a(1), 'sigma', calibGamma0.b(1));
hw_CS_2023 = struct('a', calibGamma0.a(2), 'sigma', calibGamma0.b(2));


frequencies = {'quarterly', 'semiannual'};
settlementDates = [settlementDate, settlementDate_2];
hwCS = {hw_CS_2022, hw_CS_2023};
knownFixingsTask6 = {[], knownFixing_2023};  % 2022 no historical fixing override, 2023 with known fixing

for y = 1:numel(yearLabels)
    yearLabel = yearLabels(y);
    hw = hwCS{y};
    knownFixingOpt = knownFixingsTask6{y};

    fprintf('\n--- REFERENCE DATE: %s ---\n', yearLabel);
    fprintf('Parameters HW (CS, gamma=0) from calibration (task 5) (%s): a = %.8f, sigma (b) = %.8f\n\n', ...
        yearLabel, hw.a, hw.sigma);

    for i = 1:numel(frequencies)
        freq = frequencies{i};
        for j = 1:numel(cdsSpreads)
            cds = cdsSpreads(j);

            if isempty(knownFixingOpt)
                [NPV_riskfree, CVA, final_price] = price_amortizing_swap_cva_hw(hw, ...
                    swapData, OISBoots{y}, EURBoots{y}, settlementDates(y), fixedRate, ...
                    isPayer, freq, cds, LGD);
            else
                [NPV_riskfree, CVA, final_price] = price_amortizing_swap_cva_hw(hw, ...
                    swapData, OISBoots{y}, EURBoots{y}, settlementDates(y), fixedRate, ...
                    isPayer, freq, cds, LGD, knownFixingOpt);
            end

            fprintf("Freq: %-10s | CDS: %3d bps | NPV_riskfree: %10.2f EUR | CVA: %10.2f EUR | Final NPV: %10.2f EUR\n", ...
                freq, round(cds*10000), NPV_riskfree, CVA, final_price);
        end
    end
end

toc
