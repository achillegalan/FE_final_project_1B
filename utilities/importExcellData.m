function data = importExcellData(filename, sheetName, columns, scalingFactors)
% IMPORTSHEETDATA  Generic importer for any tabular Excel sheet.
%
% INPUTS:
%   filename       - Path to the .xlsx file.
%   sheetName      - Name of the sheet to read.
%   columns        - Cell array of column names to extract (must match headers).
%   scalingFactors - (Optional) numeric vector, same length as columns.
%                    Each column is multiplied by its factor. Default: all 1s.
%                    Use NaN to skip scaling on a specific column.
%
% OUTPUT:
%   data - Scalar struct; each field is named after the cleaned column name
%          (spaces stripped, leading/trailing whitespace removed).
%
% EXAMPLES:
%   % Curve data (rates need /100 conversion)
%   curveData = importSheetData('curves.xlsx', 'EUR6M', ...
%       {'Term', 'Market Rate', 'Zero Rate', 'Discount'}, ...
%       [1, 1/100, 1/100, 1]);
%
%   % Swap amortizing plan (no scaling needed)
%   swapData = importSheetData('SwapAmortizingPlan_v1.xlsx', 'SwapPlan', ...
%       {'Pay Date', 'Accrual Start', 'Accrual End', 'Days', 'Notional'});

% --- Input validation ---
arguments
    filename       (1,:) char
    sheetName      (1,:) char
    columns        (1,:) cell
    scalingFactors (1,:) double = ones(1, numel(columns))
end

if numel(scalingFactors) ~= numel(columns)
    error('importSheetData:sizeMismatch', ...
        'scalingFactors must have the same length as columns (%d).', numel(columns));
end

% --- Read ---
dataTable = readtable(filename, ...
    'Sheet', sheetName, ...
    'VariableNamingRule', 'preserve');

% Validate requested columns exist
missing = setdiff(columns, dataTable.Properties.VariableNames);
if ~isempty(missing)
    error('importSheetData:missingColumns', ...
        'Column(s) not found in sheet "%s": %s', ...
        sheetName, strjoin(missing, ', '));
end

dataTable = dataTable(:, columns);

% --- Build output struct ---
data = struct();

for i = 1:numel(columns)
    col = columns{i};
    values = dataTable.(col);
    factor = scalingFactors(i);

    % Apply scaling only to numeric columns and only if factor is not NaN
    if isnumeric(values) && ~isnan(factor) && factor ~= 1
        values = values .* factor;
    end

    % Warn on NaNs for numeric columns
    if isnumeric(values) && any(isnan(values))
        warning('importSheetData:NaNFound', ...
            'NaN values found in column "%s" of sheet "%s".', col, sheetName);
    end

    fieldName = matlab.lang.makeValidName(col);   % e.g. "Market Rate" -> "Market_Rate"
    data.(fieldName) = values;
end

end