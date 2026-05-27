addpath('data');
addpath('bootstrap');
addpath('utilities');
addpath('pricing');

% 2022
refDate = datetime(2022, 6, 26);
settlementDate = add_target_business_days(refDate, 2);
curveFile  = fullfile('data', '20220626_Curve.xlsx');
curveColumns = {'Term', 'Market Rate'};
OIS_Curve = importExcellData(curveFile, 'OIS ESTR Curve', curveColumns);
EUR3M_Curve = importExcellData(curveFile, '3MCurve', curveColumns);
OIS_Boot = bootstrapOIS(settlementDate, OIS_Curve);
EUR3M_Boot = bootstrapCrab3M(EUR3M_Curve, OIS_Boot, settlementDate, false);

% 2023
refDate_2 = datetime(2023, 1, 31);
settlementDate_2 = add_target_business_days(refDate_2, 2);
curveFile_2  = fullfile('data', '20230131_Curve.xlsx');
OIS_Curve_2   = importExcellData(curveFile_2, 'Curva OIS 31 Jan', curveColumns);
EUR3M_Curve_2 = importExcellData(curveFile_2, 'Curve 3M 31 Jan',  curveColumns);
OIS_Boot_2 = bootstrapOIS(settlementDate_2, OIS_Curve_2);
EUR3M_Boot_2 = bootstrapCrab3M(EUR3M_Curve_2, OIS_Boot_2, settlementDate_2, false);

diagSwaptions2022 = table( ...
    ["1y"; "3y"; "5y"; "8y"; "10y"; "12y"; "15y"], ...
    ["15y"; "12y"; "10y"; "7y"; "5y"; "3y"; "1y"], ...
    [106.52; 91.17; 84.75; 78.38; 76.55; 76.63; 76.42], ...
    'VariableNames', {'Expiry','Tenor','NormalVol_bps'});
diagSwaptions2023 = table( ...
    ["1y"; "3y"; "5y"; "8y"; "10y"; "12y"; "15y"], ...
    ["15y"; "12y"; "10y"; "7y"; "5y"; "3y"; "1y"], ...
    [95.95; 90.41; 84.93; 80.43; 78.77; 79.46; 79.97], ...
    'VariableNames', {'Expiry','Tenor','NormalVol_bps'});

diagMkt2022 = buildDiagonalSwaptionMarketData(OIS_Boot, EUR3M_Boot, diagSwaptions2022, true, "quarterly");
diagMkt2023 = buildDiagonalSwaptionMarketData(OIS_Boot_2, EUR3M_Boot_2, diagSwaptions2023, true, "quarterly");

gammas = [0, 0.5, 1];
for g = gammas
    [a22, b22, cal22] = calibrateMHWabDiagonal(OIS_Boot, EUR3M_Boot, diagMkt2022, g, true, [0.10, 0.01]);
    [a23, b23, cal23] = calibrateMHWabDiagonal(OIS_Boot_2, EUR3M_Boot_2, diagMkt2023, g, true, [0.10, 0.01]);
    fprintf('gamma=%0.2f | 2022: a=%0.12g b=%0.12g SSE=%0.12g RMSE=%0.12g | 2023: a=%0.12g b=%0.12g SSE=%0.12g RMSE=%0.12g\n', ...
        g, a22, b22, cal22.sse, cal22.rmse, a23, b23, cal23.sse, cal23.rmse);
end
