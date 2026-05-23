function t_dates = convertTermToDays(termStrings, settlementDate, varargin)
%CONVERTTERMTODAYS Convert market terms to adjusted dates.
%
% INPUTS:
%   termStrings    - Scalar or vector of terms (char/string/cellstr), e.g.
%                    {'1 WK','1 MO','1 YR','ERH3'}.
%   settlementDate - Datetime scalar (curve settlement date).
%
% NAME-VALUE OPTIONS:
%   'FuturesDate'  - Which date to return for ER futures:
%                    'end' (default) | 'start' | 'expiry'
%   'OnUnknownTerm'- Behavior for unrecognized terms:
%                    'error' (default) | 'warning' | 'nan'
%
% OUTPUTS:
%   t_dates - Column datetime vector of adjusted dates.

    if nargin < 2 || isempty(settlementDate)
        error('convertTermToDays:missingSettlementDate', ...
            'convertTermToDays requires settlementDate.');
    end

    opts = parseOptions(varargin{:});

    terms = string(termStrings);
    terms = strtrim(terms(:));

    n = numel(terms);
    t_dates = NaT(n, 1);

    for i = 1:n
        term = upper(terms(i));

        % 3M Futures code (e.g. ERH3 / ERH30)
        if startsWith(term, "ER")
            try
                [startDate, endDate] = future3mDates(term, settlementDate);
                if opts.FuturesDate == "end"
                    rawDate = endDate;
                else
                    rawDate = startDate; % 'start' and 'expiry' map to IMM date
                end
                t_dates(i) = modifiedFollowing(rawDate);
            catch ME
                if shouldStopOnUnknown(term, opts.OnUnknownTerm, ME.message)
                    rethrow(ME);
                end
            end
            continue
        end

        tokens = regexp(char(term), '^(\d+\.?\d*)\s*(DY|WK|MO|YR)$', 'tokens', 'once');
        if isempty(tokens)
            if shouldStopOnUnknown(term, opts.OnUnknownTerm, '')
                error('convertTermToDays:unknownTerm', 'Cannot parse term: "%s"', char(term));
            end
            continue
        end

        num = str2double(tokens{1});
        unit = tokens{2};

        switch unit
            case 'DY'
                rawDate = settlementDate + caldays(num);
            case 'WK'
                rawDate = settlementDate + calweeks(num);
            case 'MO'
                rawDate = settlementDate + calmonths(num);
            case 'YR'
                rawDate = settlementDate + calyears(num);
            otherwise
                if shouldStopOnUnknown(term, opts.OnUnknownTerm, '')
                    error('convertTermToDays:unknownUnit', 'Unknown unit: "%s"', unit);
                end
                continue
        end

        t_dates(i) = modifiedFollowing(rawDate);
    end
end

function opts = parseOptions(varargin)
    opts = struct();
    opts.FuturesDate = "end";
    opts.OnUnknownTerm = "error";

    if isempty(varargin)
        return
    end

    if mod(numel(varargin), 2) ~= 0
        error('convertTermToDays:invalidNameValue', ...
            'Optional arguments must be passed as name-value pairs.');
    end

    for k = 1:2:numel(varargin)
        name = lower(strtrim(string(varargin{k})));
        value = lower(strtrim(string(varargin{k+1})));

        switch name
            case "futuresdate"
                if ~ismember(value, ["end", "start", "expiry"])
                    error('convertTermToDays:invalidFuturesDate', ...
                        'FuturesDate must be ''end'', ''start'', or ''expiry''.');
                end
                opts.FuturesDate = value;

            case "onunknownterm"
                if ~ismember(value, ["error", "warning", "nan"])
                    error('convertTermToDays:invalidOnUnknownTerm', ...
                        'OnUnknownTerm must be ''error'', ''warning'', or ''nan''.');
                end
                opts.OnUnknownTerm = value;

            otherwise
                error('convertTermToDays:unknownOption', ...
                    'Unknown option "%s".', char(string(varargin{k})));
        end
    end
end

function stop = shouldStopOnUnknown(term, onUnknownTerm, details)
    stop = (onUnknownTerm == "error");
    if stop || onUnknownTerm == "nan"
        return
    end

    if ~isempty(details)
        warning('convertTermToDays:unknownTerm', ...
            'Cannot parse term "%s". %s', char(term), char(string(details)));
    else
        warning('convertTermToDays:unknownTerm', ...
            'Cannot parse term "%s".', char(term));
    end
end
