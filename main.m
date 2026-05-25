% Final Project - Group 1b
% Achille Galante, Salvatore Ippolito, Ginevra Angelica Marelli
clc
clear all
rng(1234);
format long g

addpath('data')
addpath('bootstrap')
addpath('utilities')
addpath('pricing')

%% LOADING DATASET
% 2022
% tradeDate = datetime(2022, 6, 24);  --> usando questo come refDate, esce la stessa cosa per il settlement
% una differenza cambierà nelle yearfract leggermente (RISENTIRE COSA DICE LOCATELLI)
refDate = datetime(2022, 6, 26);
settlementDate = add_target_business_days(refDate, 2);
curveFile  = fullfile('data', '20220626_Curve.xlsx');  
curveColumns  = {'Term', 'Market Rate'};

OIS_Curve = importExcellData(curveFile, 'OIS ESTR Curve', curveColumns);
EUR3M_Curve = importExcellData(curveFile, '3MCurve', curveColumns);

% 2023
refDate_2 = datetime(2023, 1, 31);
settlementDate_2 = add_target_business_days(refDate_2, 2);
curveFile_2  = fullfile('data', '20230131_Curve.xlsx');  
curveColumns  = {'Term', 'Market Rate'};

OIS_Curve_2   = importExcellData(curveFile_2, 'Curva OIS 31 Jan', curveColumns);
EUR3M_Curve_2 = importExcellData(curveFile_2, 'Curve 3M 31 Jan',  curveColumns);

% Swap Amortizing
swapData = importExcellData('SwapAmortizingPlan_v1.xlsx', 'SwapPlan', ...
    {'Pay Date', 'Accrual Start', 'Accrual End', 'Days', 'Notional'});

%% 2022 curves
OIS_Boot = bootstrapOIS(settlementDate, OIS_Curve);
EUR3M_Boot = bootstrapCrab3M(EUR3M_Curve, OIS_Boot, settlementDate, true);
% disp('=== EUR3M CRAB - NODI BOOTSTRAP ===')
% disp(EUR3M_Boot.nodesTable)
% disp('=== EUR3M CRAB - TUTTE LE DATE CALCOLATE ===')
% disp(EUR3M_Boot.table)

%% 2023 curves
OIS_Boot_2 = bootstrapOIS(settlementDate_2, OIS_Curve_2);
EUR3M_Boot_2 = bootstrapCrab3M(EUR3M_Curve_2, OIS_Boot_2, settlementDate_2, true);
%disp(EUR3M_Boot_2.table)

%% Plot: OIS discount curve 2022 vs 2023 (MA ANCHE DA TOGLIERE)
tau22 = yearfrac(settlementDate, OIS_Boot.dates, 3);
tau23 = yearfrac(settlementDate_2, OIS_Boot_2.dates, 3);

% figure;
% plot(tau22, OIS_Boot.discounts, '-o', 'LineWidth', 1.3, 'DisplayName', 'OIS 2022');
% hold on;
% plot(tau23, OIS_Boot_2.discounts, '-s', 'LineWidth', 1.3, 'DisplayName', 'OIS 2023');
% grid on;
% xlabel('Maturity (years)');
% ylabel('Discount Factor');
% title('OIS Discount Curves: 2022 vs 2023');
% legend('Location','best');


%% task 2: NPV_riskfree Ammortized Swap
fixedRate = 0.0221;

%COMMENT: settledate computed as before leads to 28th, so good
% maturityYears = 15; paymentsPerYear = 4; 
% totalPeriods = maturityYears * paymentsPerYear;
% monthIncrements = calmonths(3 * (1:totalPeriods)');

% payments_dates = settlementDate + monthIncrements;
% payments_dates_adjusted = modifiedFollowing(payments_dates);
% tutta questa parte è identica a  una riga sotto
payments_dates_adjusted = swapData.PayDate;

curveDates = OIS_Boot.dates;
pseudocurveDates = EUR3M_Boot.dates;

%%
swap_quarterly = AmmortizedSwapPricer(payments_dates_adjusted, curveDates, pseudocurveDates, ...
    swapData.Notional, OIS_Boot.zeroRates, EUR3M_Boot.zeroRates, fixedRate, ...
    settlementDate)
swap_semiannual = AmmortizedSwapPricer(payments_dates_adjusted, curveDates, pseudocurveDates, ...
    swapData.Notional, OIS_Boot.zeroRates, EUR3M_Boot.zeroRates, fixedRate, ...
    settlementDate, 'semiannual')  
fprintf("Swap price from Bank perspective (MtM) is: %.2f EUR\n", swap);

