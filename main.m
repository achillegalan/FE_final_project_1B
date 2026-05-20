% Final Project - Group 1b
% Achille Galante, Salvatore Ippolito, Ginevra Angelica Marelli
clc
clear all
rng(1234);
format long g

addpath('data')
addpath('bootstrap')
addpath('utilities')

%%
% Ref Date and Curve
refDate = datetime(2023, 1, 31);
%COMMENT: needed to compute the settlementdate = refdate + 2 in a
%consistent way, now just to test function
settlementDate = refDate + days(2);

curveFile  = fullfile('data', '20230131_Curve.xlsx');  % just the .xlsx, no sheet name

OIS_Curve   = importMarketData(curveFile, 'Curva OIS 31 Jan');
EUR3M_Curve = importMarketData(curveFile, 'Curve 3M 31 Jan');
%TESTED! It should work

%%
t_dates = convertTermToDays(OIS_Curve.Term, settlementDate);

P_D_calculated = discountingBootstrapOIS(settlementDate, OIS_Curve.MarketRate, t_dates);

% Example: Accessing the first 5 discount factors of the OIS curve
disp('First 5 OIS Discount Factors:');
disp(OIS_Curve.Discount(1:5));

figure;
plot(t_dates, OIS_Curve.Discount, 'r-*', 'DisplayName', 'Vendor Discount');
hold on;
plot(t_dates, P_D_calculated, 'b-*', 'DisplayName', 'My Bootstrap');
xlabel('Days to Maturity'); ylabel('Discount Factor');
legend; title('Bootstrap Verification');

