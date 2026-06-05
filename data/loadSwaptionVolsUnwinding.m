function volsData = loadSwaptionVolsUnwinding()
% LOADSWAPTIONVOLSUNWINDING Loads the Bachelier swaption volatility cube for the project.
%   Reference Date: 31-Jan-2023 (Unwinding Date) 
%   Source Data: Bloomberg / ICAP dataset 

    % Define the coordinate axis metadata (Expiries and Tenors in years) 
    settlementDate = datetime(2023, 1, 31); 
    
    % Define the target months corresponding to each matrix row grid point
    expiryMonths = [1, 3, 6, 9, 12, 24, 36, 48, 60, 72, 84, 96, 108, 120, 144, 180, 240, 300, 360];
    numExpiries = length(expiryMonths);
    
    % Pre-allocate the dynamic target coordinates as a native datetime array
    expiryDates = NaT(numExpiries, 1);
    volsData.expiriesNum = zeros(1, numExpiries);
    
    % Compute the EXACT dynamic market-standard option expiry target dates
    for i = 1:numExpiries
        % Roll forward using the Modified Following convention as dictated by the termsheet
        expiryDates(i) = add_target_months(settlementDate, expiryMonths(i), 'modifiedfollow');
        
        % Calculate the precise interpolation coordinate using standard day-count rules
        volsData.expiriesNum(i) = yearfrac(settlementDate, expiryDates(i), 3); 
    end
    volsData.expiriesStr = {'1Mo','3Mo','6Mo','9Mo','1Yr','2Yr','3Yr','4Yr','5Yr',...
                            '6Yr','7Yr','8Yr','9Yr','10Yr','12Yr','15Yr','20Yr','25Yr','30Yr'}; 

    volsData.tenorsStr   = {'1Yr','2Yr','3Yr','4Yr','5Yr','7Yr','10Yr','12Yr','15Yr','20Yr','25Yr','30Yr'}; 
    volsData.tenorsNum   = [1, 2, 3, 4, 5, 7, 10, 12, 15, 20, 25, 30];

    % Raw Bachelier Volatility Matrix (values in bps) from the Unwinding Date dataset 
    volsData.matrix = [ ...
        %1Y      2Y      3Y      4Y      5Y      7Y      10Y     12Y     15Y     20Y     25Y     30Y
        94.86,  112.59, 111.78, 112.44, 113.67, 114.22, 114.82, 114.86, 114.87, 111.97, 106.54, 102.40;  % 1Mo 
        92.16,  105.61, 104.57, 105.74, 107.19, 106.44, 105.76, 105.56, 105.22, 103.83, 101.15, 99.38;   % 3Mo 
        91.98,  99.38,  99.17,  100.26, 101.75, 101.24, 101.10, 101.11, 101.07, 99.57,  98.08,  96.94;   % 6Mo 
        87.52,  93.94,  95.79,  97.29,  98.41,  99.06,  98.81,  98.48,  97.93,  95.86,  94.61,  93.18;   % 9Mo 
        86.60,  92.45,  94.25,  95.42,  96.56,  97.61,  97.23,  96.74,  95.95,  93.56,  92.06,  91.01;   % 1Yr 
        91.24,  94.18,  94.66,  94.91,  94.97,  95.01,  95.00,  93.82,  91.98,  90.30,  88.41,  87.10;   % 2Yr 
        93.22,  94.34,  93.72,  93.27,  93.08,  92.56,  91.69,  90.41,  88.42,  86.29,  84.59,  83.04;   % 3Yr 
        92.82,  93.14,  92.11,  91.51,  91.05,  90.02,  88.24,  86.74,  84.42,  82.20,  80.63,  78.95;   % 4Yr 
        91.17,  91.04,  90.21,  89.27,  88.64,  87.13,  84.93,  83.31,  80.80,  78.43,  76.70,  75.07;   % 5Yr 
        89.09,  88.98,  87.79,  86.86,  86.43,  84.76,  82.28,  80.57,  77.95,  75.50,  73.82,  72.05;   % 6Yr 
        87.25,  86.94,  85.94,  84.62,  84.06,  82.25,  79.97,  78.21,  75.54,  72.91,  71.16,  69.48;   % 7Yr 
        85.49,  85.46,  83.93,  82.97,  82.20,  80.43,  78.14,  76.27,  73.46,  70.49,  68.77,  67.14;   % 8Yr 
        84.21,  84.24,  82.49,  81.47,  80.41,  78.67,  76.25,  74.24,  71.24,  68.16,  66.48,  64.85;   % 9Yr 
        83.10,  83.16,  81.59,  80.15,  78.77,  77.00,  74.29,  72.17,  69.06,  65.98,  64.24,  62.69;   % 10Yr 
        81.35,  81.17,  79.48,  78.15,  76.66,  74.52,  71.22,  69.03,  65.79,  62.96,  61.20,  59.63;   % 12Yr 
        79.97,  79.70,  77.64,  75.64,  73.33,  70.84,  67.21,  64.86,  61.36,  58.98,  57.07,  55.33;   % 15Yr 
        77.60,  77.64,  75.17,  72.60,  70.00,  67.13,  62.95,  60.51,  56.83,  54.29,  52.60,  50.72;   % 20Yr 
        74.16,  74.18,  71.60,  68.88,  66.17,  62.89,  58.71,  56.40,  52.95,  49.92,  48.23,  46.55;   % 25Yr 
        71.91,  71.94,  69.18,  66.40,  63.23,  59.78,  55.03,  52.62,  49.00,  46.15,  44.59,  43.06    % 30Yr
    ];

    % Convert basis point values to decimal standard format for calculations
    volsData.matrixDecimal = volsData.matrix / 10000; 
end