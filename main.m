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
refDate = datetime(2022, 6, 26);
settlementDate = add_target_business_days(refDate, 2);
curveFile  = fullfile('data', '20220626_Curve.xlsx');  
curveColumns  = {'Term', 'Market Rate', 'Zero Rate', 'Discount'};
curveScaling  = [1, 1/100, 1/100, 1];   % rates: % -> decimal

OIS_Curve = importExcellData(curveFile, 'OIS ESTR Curve', curveColumns, curveScaling);
EUR3M_Curve = importExcellData(curveFile, '3MCurve', curveColumns, curveScaling);

% 2023
refDate_2 = datetime(2023, 1, 31);
settlementDate_2 = add_target_business_days(refDate_2, 2);
curveFile_2  = fullfile('data', '20230131_Curve.xlsx');  
curveColumns  = {'Term', 'Market Rate', 'Zero Rate', 'Discount'};
curveScaling  = [1, 1/100, 1/100, 1];

OIS_Curve_2   = importExcellData(curveFile_2, 'Curva OIS 31 Jan', curveColumns, curveScaling);
EUR3M_Curve_2 = importExcellData(curveFile_2, 'Curve 3M 31 Jan',  curveColumns, curveScaling);

% Swap Amortizing
swapData = importExcellData('SwapAmortizingPlan_v1.xlsx', 'SwapPlan', ...
    {'Pay Date', 'Accrual Start', 'Accrual End', 'Days', 'Notional'});

%% prova boostrap ois 2022
t_dates = convertTermtoDaysGeneralized(OIS_Curve.Term, settlementDate);

P_D_calculated = discountingBootstrapOIS(settlementDate, OIS_Curve.MarketRate, t_dates);

figure;
plot(t_dates, OIS_Curve.Discount, ['r-o'], 'DisplayName', 'Vendor Discount');
hold on;
plot(t_dates, P_D_calculated, 'b-*', 'DisplayName', 'My Bootstrap');
xlabel('Maturity Date'); ylabel('Discount Factor');
legend; title('Bootstrap Verification');

grid on; 
grid minor;
%% prova boostrap ois 2023
t_dates = convertTermToDays(OIS_Curve_2.Term, settlementDate_2);

P_D_calculated = discountingBootstrapOIS(settlementDate_2, OIS_Curve_2.MarketRate, t_dates);

figure;
plot(t_dates, OIS_Curve_2.Discount, 'r-o', 'DisplayName', 'Vendor Discount');
hold on;
plot(t_dates, P_D_calculated, 'b-*', 'DisplayName', 'My Bootstrap');
xlabel('Maturity Date'); ylabel('Discount Factor');
legend; title('Bootstrap Verification');

grid on; 
grid minor;

%% task 2: NPV_riskfree Ammortized Swap

%COMMENT: obviously everything must be still made looking good
fixedRate = 0.0221;

%COMMENT: settledate computed as before leads to 28th, so good
maturityYears = 15; paymentsPerYear = 4; 
totalPeriods = maturityYears * paymentsPerYear;
monthIncrements = calmonths(3 * (1:totalPeriods)');

payments_dates = settlementDate + monthIncrements;
payments_dates_adjusted = modifiedFollowing(payments_dates);

curveDates = convertTermtoDaysGeneralized(OIS_Curve.Term, settlementDate);
pseudocurveDates = convertTermtoDaysGeneralized(EUR3M_Curve.Term, settlementDate);

%%
swap = AmmortizedSwapPricer(payments_dates_adjusted, curveDates, pseudocurveDates, ...
    swapData.Notional, OIS_Curve.ZeroRate, EUR3M_Curve.ZeroRate, fixedRate, ...
    settlementDate);
disp(swap)