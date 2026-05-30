function [aCal, bCal, calib] = calibrateMHWabDiagonalHybrid( ...
    OIS_curve, EUR3M_curve, diagData, gamma, isPayer, isCS)
%CALIBRATEMHWABDIAGONALHYBRID Calibrate MHW (a,b) using GA + fmincon.
%
% This routine calibrates parameters a and b for a fixed gamma by minimizing:
%   SSE(a,b) = sum_i (ModelPrice_i(a,b,gamma) - MarketPrice_i)^2
% over the diagonal swaption set.
%
% The optimization settings are intentionally fixed in code (no user options),
% so each run uses the same default configuration.
%
% INPUT
%   OIS_curve, EUR3M_curve : Bootstrapped curve structs.
%   diagData               : Output of buildDiagonalSwaptionMarketData with
%                            field .summary containing:
%                            ExpiryYears, TenorYears, StrikeATM, MarketPrice.
%   gamma                  : Fixed gamma value.
%   isPayer                : true/false, default true.
%   isCS                   : true for cash settle, false for physical delivery.
%                            Default true.
%
% OUTPUT
%   aCal, bCal             : Calibrated parameters.
%   calib                  : Diagnostics struct (SSE, RMSE, residuals, tables,
%                            and optimizer outputs).

    if nargin < 5 || isempty(isPayer)
        isPayer = true;
    end
    if nargin < 6 || isempty(isCS)
        isCS = true;
    end

    % Fixed calibration configuration.
    cfg = struct();
    cfg.lb = [0, 0];
    cfg.ub = [0.40, 0.40];
    cfg.populationSize = 120;
    cfg.maxGenerations = 80;
    cfg.maxStallGenerations = 30;
    cfg.gaFunctionTolerance = 1e-10;
    cfg.localAlgorithm = 'sqp';
    cfg.localMaxIterations = 3000;
    cfg.localMaxFunctionEvaluations = 20000;
    cfg.localStepTolerance = 1e-9;
    cfg.localFunctionTolerance = 1e-12;
    cfg.display = 'off';
    cfg.useParallel = false;
    cfg.randomSeed = [];
    cfg.cacheObjective = true;
    cfg.aZeroTolerance = 1e-12;

    % Defensive validation for fixed bounds and tolerances.
    cfg.lb = cfg.lb(:).';
    cfg.ub = cfg.ub(:).';
    if numel(cfg.lb) ~= 2 || numel(cfg.ub) ~= 2 || ...
            any(~isfinite([cfg.lb, cfg.ub])) || any(cfg.lb < 0) || any(cfg.ub <= cfg.lb)
        error('calibrateMHWabDiagonalHybrid:InvalidBounds', ...
            'Internal bounds must satisfy 0 <= lb < ub component-wise.');
    end
    if ~isscalar(cfg.aZeroTolerance) || ~isfinite(cfg.aZeroTolerance) || cfg.aZeroTolerance < 0
        error('calibrateMHWabDiagonalHybrid:InvalidZeroTolerance', ...
            'Internal aZeroTolerance must be finite and non-negative.');
    end

    if ~isempty(cfg.randomSeed)
        rng(cfg.randomSeed);
    end

    % Extract market data vectors.
    mkt = diagData.summary;
    expiryYears = mkt.ExpiryYears(:);
    tenorYears = mkt.TenorYears(:);
    strikeATM = mkt.StrikeATM(:);
    marketPrices = mkt.MarketPrice(:);

    nSwaptions = numel(expiryYears);
    settleDate = OIS_curve.settlementDate;

    % Precompute schedules once to avoid rebuilding them at each objective call.
    floatPayDatesCell = cell(nSwaptions, 1);
    fixedPayDatesCell = cell(nSwaptions, 1);
    for i = 1:nSwaptions
        exDate = add_target_months(settleDate, round(12 * expiryYears(i)), 'modifiedfollow');
        matDate = add_target_months(exDate, round(12 * tenorYears(i)), 'modifiedfollow');

        % Convention used here: 3M floating leg and 12M fixed leg.
        floatSched = makeSchedule(exDate, matDate, 3, 'modifiedfollow');
        fixedSched = makeSchedule(exDate, matDate, 12, 'modifiedfollow');

        floatPayDatesCell{i} = floatSched(2:end);
        fixedPayDatesCell{i} = fixedSched(2:end);
    end

    % Optional cache to reuse repeated (a,b) objective evaluations.
    if cfg.cacheObjective
        sseCache = containers.Map('KeyType', 'char', 'ValueType', 'double');
    else
        sseCache = [];
    end

    gaOpts = optimoptions('ga', ...
        'Display', cfg.display, ...
        'PopulationSize', cfg.populationSize, ...
        'MaxGenerations', cfg.maxGenerations, ...
        'MaxStallGenerations', cfg.maxStallGenerations, ...
        'FunctionTolerance', cfg.gaFunctionTolerance, ...
        'UseParallel', cfg.useParallel);

    [xGA, sseGA, exitflagGA, outputGA] = ga( ...
        @objectiveAB, 2, [], [], [], [], cfg.lb, cfg.ub, [], gaOpts);

    if any(~isfinite(xGA))
        xGA = [0.1, 0.1];
    end
    xGA = min(max(xGA(:).', cfg.lb), cfg.ub);
    [xGA(1), xGA(2)] = sanitizeAB(xGA(1), xGA(2));

    fminOpts = optimoptions('fmincon', ...
        'Display', cfg.display, ...
        'Algorithm', cfg.localAlgorithm, ...
        'StepTolerance', cfg.localStepTolerance, ...
        'FunctionTolerance', cfg.localFunctionTolerance, ...
        'MaxIterations', cfg.localMaxIterations, ...
        'MaxFunctionEvaluations', cfg.localMaxFunctionEvaluations);

    [xOpt, sseMin, exitflagLocal, outputLocal] = fmincon( ...
        @objectiveAB, xGA, [], [], [], [], cfg.lb, cfg.ub, [], fminOpts);

    [aCal, bCal] = sanitizeAB(xOpt(1), xOpt(2));

    [modelPrices, ok] = modelPricesFromParams(aCal, bCal);
    if ~ok
        error('calibrateMHWabDiagonalHybrid:PricingFailureAtOptimum', ...
            'Model pricing failed at the calibrated parameters.');
    end

    residuals = modelPrices - marketPrices;
    absErrors = abs(residuals);
    rmse = sqrt(mean(residuals.^2));

    resultsTable = table(expiryYears, tenorYears, strikeATM, marketPrices, ...
        modelPrices, residuals, absErrors, ...
        'VariableNames', {'ExpiryYears','TenorYears','StrikeATM', ...
        'MarketPrice','ModelPrice','Residual','AbsError'});

    calib = struct();
    calib.method = 'ga+fmincon';
    calib.a = aCal;
    calib.b = bCal;
    calib.gamma = gamma;
    calib.sse = sseMin;
    calib.rmse = rmse;
    calib.marketPrices = marketPrices;
    calib.modelPrices = modelPrices;
    calib.residuals = residuals;
    calib.resultsTable = resultsTable;
    calib.settings = cfg;

    calib.ga = struct( ...
        'x', xGA, ...
        'sse', sseGA, ...
        'exitflag', exitflagGA, ...
        'output', outputGA);

    calib.local = struct( ...
        'x0', xGA, ...
        'x', xOpt, ...
        'sse', sseMin, ...
        'exitflag', exitflagLocal, ...
        'output', outputLocal);

    function sse = objectiveAB(x)
        [aTry, bTry] = sanitizeAB(x(1), x(2));

        if cfg.cacheObjective
            key = sprintf('%.12g|%.12g', aTry, bTry);
            if isKey(sseCache, key)
                sse = sseCache(key);
                return;
            end
        end

        [modelTry, okTry] = modelPricesFromParams(aTry, bTry);
        if ~okTry || any(~isfinite(modelTry))
            sse = 1e30;
            if cfg.cacheObjective
                sseCache(key) = sse;
            end
            return;
        end

        r = modelTry - marketPrices;
        sse = sum(r.^2);
        if ~isfinite(sse)
            sse = 1e30;
        end

        if cfg.cacheObjective
            sseCache(key) = sse;
        end
    end

    function [modelVec, flag] = modelPricesFromParams(aTry, bTry)
        [aTry, bTry] = sanitizeAB(aTry, bTry);
        modelVec = zeros(nSwaptions, 1);
        flag = true;

        for j = 1:nSwaptions
            try
                modelVec(j) = model_multiHJM_Price( ...
                    OIS_curve, EUR3M_curve, ...
                    floatPayDatesCell{j}, fixedPayDatesCell{j}, ...
                    strikeATM(j), expiryYears(j), ...
                    aTry, bTry, gamma, isPayer, isCS);
            catch
                flag = false;
                return;
            end
        end
    end

    function [aOut, bOut] = sanitizeAB(aIn, bIn)
        % Keep non-negative values and snap near-zero values to exactly zero.
        aOut = max(0, aIn);
        bOut = max(0, bIn);

        if aOut <= cfg.aZeroTolerance
            aOut = 0;
        end
        if bOut <= cfg.aZeroTolerance
            bOut = 0;
        end
    end
end
