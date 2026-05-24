function curve = bootstrapCrab3M(mkt, oisCurve, settlementDate, flag)

%BOOTSTRAPCRAB3M Builds the Euribor 3M pseudo-discount curve using Crab bootstrap.
%
% INPUTS:
%   mkt            Market data table/struct with Term and MarketRate.
%   oisCurve       OIS discount curve used for discounting.
%   settlementDate Curve settlement date.
%   flag           Optional logical flag; if true, plots OIS vs EUR3M zero rates.
%
% OUTPUT:
%   curve          Struct containing:
%                    - settlementDate: curve settlement date.
%                    - dates: bootstrap node dates.
%                    - discounts: pseudo-discount factors on bootstrap nodes.
%                    - zeroRates: zero rates computed from bootstrap discounts.
%                    - allDates: all relevant calculation dates used by the curve.
%                    - allDiscounts: interpolated pseudo-discount factors on allDates.
%                    - allZeroRates: zero rates computed from allDiscounts.
%                    - nodesTable: table with Date, Discount, ZeroRate on bootstrap nodes.
%                    - table: table with Date, Discount, ZeroRate on all calculation dates.

    %% Default : no plot
    if nargin < 4 || isempty(flag)
        doPlot = false;
    else
        if ~(islogical(flag) || isnumeric(flag)) || ~isscalar(flag)
            error('Optional input doPlot must be a scalar logical (true/false).');
        end
        doPlot = logical(flag);
    end

    %% Initialization
    terms = string(mkt.Term(:));   
    rates = mkt.MarketRate(:);

    curveDates = settlementDate;
    curveDisc = 1.0;
    allCalcDates = settlementDate;

    %% 1. Deposit 3M 
    depIdx = find(terms == "3 MO", 1);

    depRate = rates(depIdx);
    depEnd = add_target_months(settlementDate, 3, 'modifiedfollow');  
    deltaDep = yearfrac(settlementDate, depEnd, 2); % ACT/360
    depDisc = 1/(1+deltaDep*depRate);               % Compute discount

    curveDates(end+1,1) = depEnd;
    curveDisc(end+1,1) = depDisc;
    allCalcDates(end+1,1) = depEnd;

    %% 2. Futures treated as FRA (no convexity adjustment)
    % find the futures dates and sort them in cronological order
    futIdx = find(startsWith(terms, "ER"));
    nFut = numel(futIdx);
    futStart = NaT(nFut,1);
    futEnd = NaT(nFut,1);

    for k = 1:nFut
        [futStart(k), futEnd(k)] = future3mDates(terms(futIdx(k)), settlementDate);
    end

    [~, ord] = sort(futStart);
    futIdx = futIdx(ord);
    futStart = futStart(ord);
    futEnd = futEnd(ord);

    % Use only futures with start date <= 2Y from settlement
    cutoff2Y = add_target_months(settlementDate, 24, 'modifiedfollow');
    keep = futStart <= cutoff2Y;
    futIdx = futIdx(keep);
    futStart = futStart(keep);
    futEnd = futEnd(keep);

    futDelta = yearfrac(futStart, futEnd, 2); % ACT/360
    allCalcDates = [allCalcDates; futStart; futEnd];

    % loop on futures
    for k = 1:numel(futIdx)
        futRate = rates(futIdx(k));
        startDate = futStart(k);
        endDate = futEnd(k);
        deltaFut = futDelta(k);

        % Interpolation on start Date
        Pstart = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, startDate, curveDates, curveDisc);
        Pend = Pstart / (1 + deltaFut * futRate);

        if ~any(curveDates == endDate)
            curveDates(end+1,1) = endDate;
            curveDisc(end+1,1)  = Pend;
        end
    end

    [curveDates, idx] = sort(curveDates(:));
    curveDisc = curveDisc(idx);
    [curveDates, uniqueIdx] = unique(curveDates, 'stable');
    curveDisc = curveDisc(uniqueIdx);

   %% 3. Swaps (sequential bootstrap; vectorized preprocessing only)
    swapIdx = find(endsWith(terms, "YR"));

    if isempty(swapIdx)
        error('bootstrapCrab3M:missingSwaps', ...
            'No swap instruments (terms ending with "YR") found in market data.');
    end

    % Vectorized extraction of swap terms and rates
    swapTerms = terms(swapIdx);
    swapRates = rates(swapIdx);

    % Vectorized parsing: "5 YR" -> 5
    swapYears = str2double(extractBefore(swapTerms, " YR"));
    if any(isnan(swapYears))
        error('bootstrapCrab3M:invalidSwapTerm', ...
            'At least one swap term could not be parsed. Expected format like "5 YR".');
    end

    % Vectorized maturity-date generation, then chronological ordering
    swapMatDates = arrayfun(@(y) add_target_months(settlementDate, 12*y, 'modifiedfollow'), swapYears);
    [swapMatDates, ord] = sort(swapMatDates);
    swapRates = swapRates(ord);

    for k = 1:numel(swapMatDates)
        maturityDate = swapMatDates(k);
        swapRate = swapRates(k);

        % If this maturity is already a known node, there is nothing to bootstrap.
        if any(curveDates == maturityDate)
            continue
        end

        allCalcDates(end+1,1) = maturityDate;

        % Build coupon schedules once for this swap maturity.
        floatDates = makeSchedule(settlementDate, maturityDate, 3, 'modifiedfollow');
        fixedDates = makeSchedule(settlementDate, maturityDate, 12, 'modifiedfollow');
        allCalcDates = [allCalcDates; floatDates(:); fixedDates(:)];

        % Split floating schedule into period start/end and accrual fractions.
        floatStart = floatDates(1:end-1);
        floatEnd = floatDates(2:end);
        floatDelta = yearfrac(floatStart, floatEnd, 2); % ACT/360

        % Split fixed schedule into period start/end and accrual fractions.
        fixedPrev = fixedDates(1:end-1);
        fixedEnd = fixedDates(2:end);
        fixedDelta = yearfrac(fixedPrev, fixedEnd, 6); % 30/360

        % Precompute OIS discount factors at floating and fixed payment dates.
        % These do not depend on PN, so we compute them once (outside fzero calls).
        oisDiscFloatEnd = arrayfun(@(d) get_discount_factor_by_zero_rates_linear_interp( ...
            oisCurve.settlementDate, d, oisCurve.dates, oisCurve.discounts), floatEnd);
        oisDiscFixedEnd = arrayfun(@(d) get_discount_factor_by_zero_rates_linear_interp( ...
            oisCurve.settlementDate, d, oisCurve.dates, oisCurve.discounts), fixedEnd);

        % Cache all swap-specific constants to avoid recomputation in objective function.
        swapCache = struct();
        swapCache.floatStart = floatStart;
        swapCache.floatEnd = floatEnd;
        swapCache.floatDelta = floatDelta;
        swapCache.oisDiscFloatEnd = oisDiscFloatEnd;
        swapCache.fixedLegConst = swapRate * sum(fixedDelta .* oisDiscFixedEnd);

        % Objective: solve for PN such that floating leg - fixed leg = 0.
        obj = @(PN) swapObjectiveCrab(PN, settlementDate, ...
            maturityDate, swapRate, curveDates, curveDisc, swapCache);

        % Initial PN guess from last known node using exponential decay.
        lastDisc = curveDisc(end);
        guess = lastDisc * exp(-swapRate * yearfrac(curveDates(end), maturityDate, 3));

        % Prefer bracketed root finding; fallback to single-point start if needed.
        lower = max(1e-8, 0.30 * guess);   % enforce positive DF
        upper = min(1.50, 1.70 * guess);
        fLower = obj(lower);
        fUpper = obj(upper);

        if fLower * fUpper > 0
            PN = fzero(obj, guess);
        else
            PN = fzero(obj, [lower upper]);
        end

        % Add the solved node and keep curve vectors sorted and deduplicated.
        curveDates(end+1,1) = maturityDate;
        curveDisc(end+1,1)  = PN;

        [curveDates, idx] = sort(curveDates(:));
        curveDisc = curveDisc(idx);
        [curveDates, uniqueIdx] = unique(curveDates, 'stable');
        curveDisc = curveDisc(uniqueIdx);
    end

    %% Zero-rates 
    % for curveDates
    tau = yearfrac(settlementDate, curveDates, 3);
    zeroRates = nan(size(curveDisc));
    isAfterSettlement = tau > 0;
    zeroRates(isAfterSettlement) = -log(curveDisc(isAfterSettlement)) ./ tau(isAfterSettlement);
    
    % for allCalcDates
    allCalcDates = sort(unique(allCalcDates));
    allDisc = arrayfun(@(d) get_discount_factor_by_zero_rates_linear_interp( ...
        settlementDate, d, curveDates, curveDisc), allCalcDates);

    tauAll = yearfrac(settlementDate, allCalcDates, 3);
    allZero = nan(size(allDisc));
    isAfterSettlementAll = tauAll > 0;
    allZero(isAfterSettlementAll) = -log(allDisc(isAfterSettlementAll)) ./ tauAll(isAfterSettlementAll);

    %% Output
    curve.settlementDate = settlementDate;
    curve.dates = curveDates;
    curve.discounts = curveDisc;
    curve.zeroRates = zeroRates;
    curve.allDates = allCalcDates;
    curve.allDiscounts = allDisc;
    curve.allZeroRates = allZero;

    curve.nodesTable = table(curveDates, curveDisc, zeroRates, ...
        'VariableNames', {'Date','Discount','ZeroRate'});

    curve.table = table(allCalcDates, allDisc, allZero, ...
        'VariableNames', {'Date','Discount','ZeroRate'});

    %% Plot
    if doPlot
        if ~isfield(oisCurve, 'zeroRates') || ~isfield(oisCurve, 'dates')
            warning('bootstrapCrab3M:missingOISFields', ...
                'Cannot plot OIS vs EUR3M: oisCurve must contain fields dates and zeroRates.');
        else
            figure;
            plot(oisCurve.dates, 100 * oisCurve.zeroRates, '-o', ...
                'LineWidth', 1.3, 'DisplayName', 'OIS');
            hold on;
            plot(curve.dates, 100 * curve.zeroRates, '-s', ...
                'LineWidth', 1.3, 'DisplayName', 'EUR3M');
            grid on;
            xlabel('Date');
            ylabel('Zero Rate (%)');
            title(sprintf('OIS vs EUR3M Zero Rates (%s)', datestr(settlementDate, 'dd-mmm-yyyy')));
            legend('Location', 'best');
        end
    end
end
