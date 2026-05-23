clc
clear all
rng(1234);
format long g

addpath('PROVA_BOOSTRAP')
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

%% 2022 curves
OIS_Boot = buildCurveFromStruct(OIS_Curve, settlementDate);
EUR3M_Boot = bootstrapCrab3M(EUR3M_Curve, OIS_Boot, settlementDate);

disp('=== EUR3M CRAB - NODI BOOTSTRAP ===')
disp(EUR3M_Boot.nodesTable)
disp('=== EUR3M CRAB - TUTTE LE DATE CALCOLATE ===')
disp(EUR3M_Boot.table)

%% PLOT EUR3M PSEUDO-DISCOUNT CURVE (ALL CALCULATED DATES)
figure;
plot(EUR3M_Boot.allDates, EUR3M_Boot.allDiscounts, '-.', 'LineWidth', 1.2)
hold on
plot(EUR3M_Boot.dates, EUR3M_Boot.discounts, 'o', 'LineWidth', 1.2)
grid on
xlabel('Date')
ylabel('Pseudo-discount')
legend('All calculated dates', 'Bootstrap nodes', 'Location', 'best')
title('EURIBOR 3M Pseudo-Discount Curve - All Calculated Dates')

%% OIS VS EUR3M
figure;
plot(OIS_Boot.dates, 100 * OIS_Boot.zeroRates, '-o', 'LineWidth', 1.5)
hold on
plot(EUR3M_Boot.dates, 100 * EUR3M_Boot.zeroRates, '-s', 'LineWidth', 1.5)
grid on
xlabel('Date')
ylabel('Zero Rate (%)')
legend('OIS Discount Curve', 'EUR3M Pseudo-Curve', 'Location', 'best')
title('Multi-Curve Framework')







%% 2023
refDate_2 = datetime(2023, 1, 31);
settlementDate_2 = add_target_business_days(refDate_2, 2);
curveFile_2  = fullfile('data', '20230131_Curve.xlsx');  
OIS_Curve_2   = importMarketData(curveFile_2, 'Curva OIS 31 Jan');
EUR3M_Curve_2 = importMarketData(curveFile_2, 'Curve 3M 31 Jan');

%% 2023 curves
OIS_Boot_2 = buildCurveFromStruct(OIS_Curve_2, settlementDate_2);
EUR3M_Boot_2 = bootstrapCrab3M(EUR3M_Curve_2, OIS_Boot_2, settlementDate_2);

disp('=== EUR3M CRAB - NODI BOOTSTRAP ===')
disp(EUR3M_Boot_2.nodesTable)
disp('=== EUR3M CRAB - TUTTE LE DATE CALCOLATE ===')
disp(EUR3M_Boot_2.table)

%% PLOT EUR3M PSEUDO-DISCOUNT CURVE (ALL CALCULATED DATES)

figure;
plot(EUR3M_Boot_2.allDates, EUR3M_Boot_2.allDiscounts, '-.', 'LineWidth', 1.2)
hold on
plot(EUR3M_Boot_2.dates, EUR3M_Boot_2.discounts, 'o', 'LineWidth', 1.2)
grid on
xlabel('Date')
ylabel('Pseudo-discount')
legend('All calculated dates', 'Bootstrap nodes', 'Location', 'best')
title('EURIBOR 3M Pseudo-Discount Curve - All Calculated Dates')

%% OIS VS EUR3M
figure;
plot(OIS_Boot_2.dates, 100 * OIS_Boot_2.zeroRates, '-o', 'LineWidth', 1.5)
hold on
plot(EUR3M_Boot_2.dates, 100 * EUR3M_Boot_2.zeroRates, '-s', 'LineWidth', 1.5)
grid on
xlabel('Date')
ylabel('Zero Rate (%)')
legend('OIS Discount Curve', 'EUR3M Pseudo-Curve', 'Location', 'best')
title('Multi-Curve Framework')
