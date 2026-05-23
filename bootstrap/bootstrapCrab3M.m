function curve = bootstrapCrab3M(mkt, oisCurve, settlementDate, varargin)

%BOOTSTRAPCRAB3M Builds the Euribor 3M pseudo-discount curve using Crab bootstrap.
%
% INPUTS:
%   mkt            Market data table/struct with Term and MarketRate.
%   oisCurve       OIS discount curve used for discounting.
%   settlementDate Curve settlement date.
%   flag           Optional logical flag; if true, plots OIS vs EUR3M zero rates.
%
% OUTPUT:
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

doPlot = false;
if ~isempty(varargin)
    if numel(varargin) > 1
        error('bootstrapCrab3M:invalidInputs', ...
            'Optional input doPlot must be a single logical value.');
    end
    flag = varargin{1};
    if ~(islogical(flag) || isnumeric(flag)) || ~isscalar(flag)
        error('bootstrapCrab3M:invalidInputs', ...
            'Optional input doPlot must be a scalar logical (true/false).');
    end
    doPlot = logical(flag);
end

    terms = string(mkt.Term(:));    % converto in stinghe i Term
    rates = mkt.MarketRate(:);

    curveDates = datetime.empty(0,1);
    curveDisc  = [];
    allCalcDates = datetime.empty(0,1);

    curveDates(end+1,1) = settlementDate;
    curveDisc(end+1,1)  = 1.0;
    allCalcDates(end+1,1) = settlementDate;


    %% ===  1. Deposit 3M   ===
    depIdx = find(terms == "3 MO", 1);
    if isempty(depIdx)
        error('3 MO deposit not found in EUR3M market data.');
    end

    depRate = rates(depIdx);
    
    depEnd = add_target_months(settlementDate, 3, 'modifiedfollow');  % aggiunge tre mesi
    deltaDep = yearfrac(settlementDate, depEnd, 2); % ACT/360

    depDisc = 1/(1+deltaDep*depRate);

    curveDates(end+1,1) = depEnd;
    curveDisc(end+1,1) = depDisc;
    allCalcDates(end+1,1) = depEnd;

    %% ===  2. Futures treated as FRA, no convexity adjustment   ===
    futIdx = find(startsWith(terms, "ER"));
    % Ordina i futures per start date (IMM) in ordine cronologico
    futStart = NaT(numel(futIdx),1);
    for k = 1:numel(futIdx)
        [sTmp, ~] = future3mDates(terms(futIdx(k)), settlementDate);
        futStart(k) = sTmp;
    end
    [~, ord] = sort(futStart);
    futIdx = futIdx(ord);
    futStart = futStart(ord);

    % Use only futures with start date <= 2Y from settlement
    cutoff2Y = add_target_months(settlementDate, 24, 'modifiedfollow');
    futIdx = futIdx(futStart <= cutoff2Y);

    for k = 1:numel(futIdx)
        idx = futIdx(k);
        futCode = terms(idx);
        futRate = rates(idx);

        [startDate, endDate] = future3mDates(futCode, settlementDate);
        deltaFut = yearfrac(startDate, endDate, 2); % ACT/360
        allCalcDates = [allCalcDates; startDate; endDate];

        % Usa interpolazione sullo start date (non match esatto dei nodi)
        if startDate < curveDates(1) || startDate > curveDates(end)
            continue
        end

        Pstart = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, startDate, curveDates, curveDisc);
        Pend = Pstart / (1 + deltaFut * futRate);

        if ~any(curveDates == endDate)
            curveDates(end+1,1) = endDate;
            curveDisc(end+1,1)  = Pend;
        end

        [curveDates, curveDisc] = sortCurve(curveDates, curveDisc);
    end

    %% ===  3. Swaps   ===
    swapIdx = find(endsWith(terms, "YR"));

    for k = 1:numel(swapIdx)
        idx = swapIdx(k);
        swapTerm = terms(idx);
        swapRate = rates(idx);
        maturityYears = sscanf(swapTerm, '%d YR');

       maturityDate = add_target_months(settlementDate, 12*maturityYears, 'modifiedfollow');

        % se abbiamo gia il nodo, salta prima di popolare allCalcDates
        if any(curveDates == maturityDate)
            continue
        end

        allCalcDates(end+1,1) = maturityDate;

        floatDates = makeSchedule(settlementDate, maturityDate, 3, 'modifiedfollow');
        fixedDates = makeSchedule(settlementDate, maturityDate, 12, 'modifiedfollow');
        allCalcDates = [allCalcDates; floatDates(:); fixedDates(:)];
        
        obj = @(PN) swapObjectiveCrab(PN, settlementDate, ...
            maturityDate, swapRate, curveDates, curveDisc, oisCurve);

        lastDisc = curveDisc(end);
        guess = lastDisc * exp(-swapRate * yearfrac(curveDates(end), maturityDate, 3));

        lower = max(1e-8, 0.30 * guess);
        upper = min(1.50, 1.70 * guess);

        fLower = obj(lower);
        fUpper = obj(upper);

        if fLower * fUpper > 0
            PN = fzero(obj, guess);
        else
            PN = fzero(obj, [lower upper]);
        end

        curveDates(end+1,1) = maturityDate;
        curveDisc(end+1,1)  = PN;

        [curveDates, curveDisc] = sortCurve(curveDates, curveDisc);
    end

    %% zero-rates & outputs
    tau = yearfrac(settlementDate, curveDates, 3);
    zeroRates = nan(size(curveDisc));
    isAfterSettlement = tau > 0;
    zeroRates(isAfterSettlement) = -log(curveDisc(isAfterSettlement)) ./ tau(isAfterSettlement);

    allCalcDates = sort(unique(allCalcDates));

    inRange = allCalcDates >= curveDates(1) & allCalcDates <= curveDates(end);
    allCalcDates = allCalcDates(inRange);

    allDisc = zeros(numel(allCalcDates),1);
    for i = 1:numel(allCalcDates)
        allDisc(i) = get_discount_factor_by_zero_rates_linear_interp( ...
            settlementDate, allCalcDates(i), curveDates, curveDisc);
    end

    tauAll = yearfrac(settlementDate, allCalcDates, 3);
    allZero = nan(size(allDisc));
    isAfterSettlementAll = tauAll > 0;
    allZero(isAfterSettlementAll) = -log(allDisc(isAfterSettlementAll)) ./ tauAll(isAfterSettlementAll);

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
