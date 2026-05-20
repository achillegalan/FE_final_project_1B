% Final Project - Group 1b
% Achille Galante, Salvatore Ippolito, Ginevra Angelica Marelli
clc
clear all
rng(1234);
format long g

addpath('data')
addpath('bootstrap')
addpath('utilities')

%% LOADING DATASET
% 2022
refDate = datetime(2022, 6, 26);
settlementDate = add_target_business_days(refDate, 2);
curveFile  = fullfile('data', '20220626_Curve.xlsx');  
OIS_Curve = importMarketData(curveFile, 'OIS ESTR Curve');
EUR3M_Curve = importMarketData(curveFile, '3MCurve');

% 2023
refDate_2 = datetime(2023, 1, 31);
settlementDate_2 = add_target_business_days(refDate_2, 2);
curveFile_2  = fullfile('data', '20230131_Curve.xlsx');  
OIS_Curve_2   = importMarketData(curveFile_2, 'Curva OIS 31 Jan');
EUR3M_Curve_2 = importMarketData(curveFile_2, 'Curve 3M 31 Jan');


%% prova boostrap ois 2022
t_dates = convertTermToDays(OIS_Curve.Term, settlementDate);

P_D_calculated = discountingBootstrapOIS(settlementDate, OIS_Curve.MarketRate, t_dates);

figure;
plot(t_dates, OIS_Curve.Discount, ['r-o'], 'DisplayName', 'Vendor Discount');
hold on;
plot(t_dates, P_D_calculated, 'b-*', 'DisplayName', 'My Bootstrap');
xlabel('Maturity Date'); ylabel('Discount Factor');
legend; title('Bootstrap Verification');


%% prova boostrap ois 2023
t_dates = convertTermToDays(OIS_Curve_2.Term, settlementDate_2);

P_D_calculated = discountingBootstrapOIS(settlementDate_2, OIS_Curve_2.MarketRate, t_dates);

figure;
plot(t_dates, OIS_Curve_2.Discount, ['r-o'], 'DisplayName', 'Vendor Discount');
hold on;
plot(t_dates, P_D_calculated, 'b-*', 'DisplayName', 'My Bootstrap');
xlabel('Maturity Date'); ylabel('Discount Factor');
legend; title('Bootstrap Verification');

