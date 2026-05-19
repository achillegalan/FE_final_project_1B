% Final Project - Group 1b
% Achille Galante, Salvatore Ippolito, Ginevra Angelica Marelli
clc
clear all
rng(1234);
format long g
addpath('data')

%%
% Ref Date and Curve
refDate = datetime(2023, 1, 31);
curveFile  = fullfile('data', '20220626_Curve.xlsx');  % just the .xlsx, no sheet name

OIS_Curve   = importMarketData(curveFile, 'OIS ESTR Curve');
EUR3M_Curve = importMarketData(curveFile, '3MCurve');

% Example: Accessing the first 5 discount factors of the OIS curve
disp('First 5 OIS Discount Factors:');
disp(OIS_Curve.Discount(1:5));
