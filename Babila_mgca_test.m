%% Babila_mgca_test.m
% Read Mg/Ca data from Babila2022_MgCa_SDB_PETM.xlsx and predict SST
% using baymag_predict, separately for prePETM and PETM intervals.
%
% baymag_predict has species-specific models. Valid species strings:
%   'ruber'     - Globigerinoides ruber (pH-sensitive)
%   'bulloides' - Globigerina bulloides (pH-sensitive)
%   'sacculifer'- Globigerinoides sacculifer
%   'pachy'     - Neogloboquadrina pachyderma
%   'incompta'  - Neogloboquadrina incompta
%   'all'       - pooled calibration, annual SST
%   'all_sea'   - pooled calibration, seasonal SST
%
% Edit the USER PARAMETERS section to match your data.

clear; clc;

%% ---- USER PARAMETERS -----------------------------------------------

% Path to the Excel file
excel_file = 'Babila2022_MgCa_SDB_PETM.xlsx';
excel_sheet = 1;

% Species mapping: Excel species name -> baymag species string
species_map = {
    'Subbotina',   'all';
    'Acarinina',   'all';
    'Morozovella', 'all';
};

% Age in Ma for seawater correction (scalar or vector of length N)
age_prePETM = 56.0;   % Ma
age_PETM    = 55.9;   % Ma

% Depth cutoffs (in meters) defining the three intervals:
%   prePETM:  depth > 204.2 m  (> 670 ft)   -- older
%   PETM:     192.0 - 204.2 m  (630-670 ft) -- peak event
%   postPETM: depth < 192.0 m  (< 630 ft)   -- younger; uses prePETM params
petm_bottom_m = 204.2;   % PETM onset  (~670 ft)
petm_top_m    = 192.0;   % PETM top    (~630 ft)

% --- prePETM environmental parameters ---
omega_prePETM    = 4.282963753;     % bottom water calcite saturation state
salinity_prePETM = 35;      % seawater salinity (psu)
pH_prePETM       = 7.745986462;     % seawater pH (total scale)

% --- PETM environmental parameters ---
omega_PETM    = 3.205500841;     % bottom water calcite saturation state
salinity_PETM = 35;      % seawater salinity (psu)
pH_PETM       = 7.491107941;   % seawater pH (total scale)

% Cleaning method: 0 = oxidative, 1 = reductive, 0-1 = mixed
clean = 1;

% Prior standard deviation on SST (degrees C). Suggested: 5-10
pstd = 10;

% Seawater Mg/Ca correction:
%   0 = no correction
%   1 = original seawater curve (Tierney et al. 2019)
%   2 = updated curve with Na/Ca (Rosenthal et al. 2022)
sw = 1;

% ---- END USER PARAMETERS --------------------------------------------

%% Read Excel file
fprintf('Reading %s ...\n', excel_file);
T = readtable(excel_file, 'Sheet', excel_sheet);
fprintf('Loaded %d rows. Columns: %s\n\n', height(T), strjoin(T.Properties.VariableNames, ', '));

%% Locate Mg/Ca column
colNames = lower(T.Properties.VariableNames);
mgcaIdx = find( ...
    strcmp(colNames, 'mgca') | ...
    strcmp(colNames, 'mg_ca') | ...
    contains(colNames, 'mg/ca') | ...
    (contains(colNames, 'mg') & contains(colNames, 'ca')), 1);
if isempty(mgcaIdx)
    error('No Mg/Ca column found. Available columns: %s', strjoin(T.Properties.VariableNames, ', '));
end
fprintf('Mg/Ca column: "%s"\n', T.Properties.VariableNames{mgcaIdx});

%% Locate depth column (meters)
depthIdx = find(contains(colNames, 'depth') & contains(colNames, 'm_'), 1);
if isempty(depthIdx)
    depthIdx = find(contains(colNames, 'depth'), 1);
end
if isempty(depthIdx)
    error('No depth column found. Available columns: %s', strjoin(T.Properties.VariableNames, ', '));
end
fprintf('Depth column:  "%s"\n\n', T.Properties.VariableNames{depthIdx});

%% Locate Species column
speciesIdx = find(strcmpi(colNames, 'species') | strcmpi(colNames, 'taxon'), 1);

%% Split table into three intervals
depth_vals   = T{:, depthIdx};
prepetm_mask = depth_vals >  petm_bottom_m;
petm_mask    = depth_vals >= petm_top_m & depth_vals <= petm_bottom_m;
postpetm_mask= depth_vals <  petm_top_m;

fprintf('Interval breakdown:\n');
fprintf('  prePETM:  %d rows (depth > %.1f m / > 670 ft)\n',          sum(prepetm_mask),  petm_bottom_m);
fprintf('  PETM:     %d rows (%.1f - %.1f m / 630-670 ft)\n',         sum(petm_mask),     petm_top_m, petm_bottom_m);
fprintf('  postPETM: %d rows (depth < %.1f m / < 630 ft)\n\n',        sum(postpetm_mask), petm_top_m);

%% Define intervals to process
% postPETM uses same omega/pH as prePETM
intervals = {
    'prePETM',  T(prepetm_mask,  :), age_prePETM, omega_prePETM, salinity_prePETM, pH_prePETM;
    'PETM',     T(petm_mask,     :), age_PETM,    omega_PETM,    salinity_PETM,    pH_PETM;
    'postPETM', T(postpetm_mask, :), age_prePETM, omega_prePETM, salinity_prePETM, pH_prePETM;
};

%% Loop over intervals and species
all_rows = table();

for iInt = 1:size(intervals, 1)
    int_name   = intervals{iInt, 1};
    Tint       = intervals{iInt, 2};
    age_Ma     = intervals{iInt, 3};
    omega      = intervals{iInt, 4};
    salinity   = intervals{iInt, 5};
    pH         = intervals{iInt, 6};

    fprintf('========== %s (omega=%.2f, pH=%.3f) ==========\n', int_name, omega, pH);

    if height(Tint) == 0
        fprintf('  No data for this interval, skipping.\n\n');
        continue;
    end

    for iSp = 1:size(species_map, 1)
        excel_species  = species_map{iSp, 1};
        baymag_species = species_map{iSp, 2};

        % Filter by species
        if ~isempty(speciesIdx)
            mask = strcmpi(Tint{:, speciesIdx}, excel_species);
        else
            mask = true(height(Tint), 1);
        end

        Tsp = Tint(mask, :);
        if height(Tsp) == 0
            fprintf('  No rows for species "%s", skipping.\n', excel_species);
            continue;
        end

        % Extract and validate Mg/Ca
        mgca = Tsp{:, mgcaIdx};
        if ~isnumeric(mgca), mgca = str2double(mgca); end
        nanMask = isnan(mgca);
        if any(nanMask)
            warning('%d NaN Mg/Ca removed for %s %s.', sum(nanMask), int_name, excel_species);
            Tsp  = Tsp(~nanMask, :);
            mgca = mgca(~nanMask);
        end

        Nobs = length(mgca);
        if Nobs < 2
            warning('%s "%s": only %d value(s), need >= 2. Skipping.', int_name, excel_species, Nobs);
            continue;
        end

        fprintf('  --- Species: %-15s | baymag: %-12s | N = %d ---\n', ...
            excel_species, baymag_species, Nobs);

        % Expand scalars to vectors
        age_vec = age_Ma   .* ones(Nobs, 1);
        om_vec  = omega    .* ones(Nobs, 1);
        sal_vec = salinity .* ones(Nobs, 1);
        ph_vec  = pH       .* ones(Nobs, 1);

        % Run baymag_predict
        output = baymag_predict(age_vec, mgca, om_vec, sal_vec, ph_vec, ...
                                clean, baymag_species, pstd, sw);

        % Convergence warnings
        if any(output.rhat > 1.1)
            warning('%d sample(s) have Rhat > 1.1 for %s %s.', ...
                sum(output.rhat > 1.1), int_name, excel_species);
        end

        % Compute p16 and p84 from ensemble
        sst_p16 = prctile(output.ens, 16, 2);
        sst_p84 = prctile(output.ens, 84, 2);

        % Attach predictions to table
        Tsp.interval       = repmat({int_name},       Nobs, 1);
        Tsp.baymag_species = repmat({baymag_species}, Nobs, 1);
        Tsp.SST_2p5  = output.SST(:, 1);
        Tsp.SST_16   = sst_p16;
        Tsp.SST_50   = output.SST(:, 2);
        Tsp.SST_84   = sst_p84;
        Tsp.SST_97p5 = output.SST(:, 3);
        Tsp.Rhat     = output.rhat;

        all_rows = [all_rows; Tsp]; %#ok<AGROW>

        % Print results
        fprintf('  %-8s  %-10s  %-8s  %-10s  %-8s  %-6s\n', ...
            'Row', 'Mg/Ca', 'SST_16%', 'SST_50%', 'SST_84%', 'Rhat');
        for i = 1:Nobs
            fprintf('  %-8d  %-10.3f  %-8.2f  %-10.2f  %-8.2f  %-6.3f\n', ...
                i, mgca(i), sst_p16(i), output.SST(i,2), sst_p84(i), output.rhat(i));
        end
        fprintf('\n');

        if isempty(speciesIdx), break; end
    end
end

%% Save results
if ~isempty(all_rows)
    out_file = 'Babila_SST_results.csv';
    writetable(all_rows, out_file);
    fprintf('Results saved to %s\n', out_file);
else
    warning('No results produced. Check depth cutoff and species names.');
    return;
end

%% Plot SST vs depth for each species
species_list  = unique(all_rows.Species, 'stable');
interval_list = {'prePETM', 'PETM', 'postPETM'};
colors  = struct('prePETM', [0.00 0.45 0.74], 'PETM', [0.85 0.33 0.10], 'postPETM', [0.47 0.67 0.19]);
markers = struct('prePETM', 's',              'PETM', 'o',               'postPETM', '^');

depth_col = T.Properties.VariableNames{depthIdx};

figure('Name', 'SST by Species', 'Position', [100 100 400*length(species_list) 500]);

for iSp = 1:length(species_list)
    sp = species_list{iSp};
    subplot(1, length(species_list), iSp);
    hold on;

    leg_handles = [];
    leg_labels  = {};

    for iInt = 1:length(interval_list)
        int_name = interval_list{iInt};
        mask = strcmp(all_rows.Species, sp) & strcmp(all_rows.interval, int_name);
        if ~any(mask), continue; end

        depth  = all_rows.(depth_col)(mask);
        sst_50 = all_rows.SST_50(mask);
        err_lo = all_rows.SST_50(mask) - all_rows.SST_16(mask);
        err_hi = all_rows.SST_84(mask) - all_rows.SST_50(mask);
        col    = colors.(int_name);
        mkr    = markers.(int_name);

        h = errorbar(sst_50, depth, err_lo, err_hi, 'horizontal', ...
            'LineStyle', 'none', 'Color', col, ...
            'Marker', mkr, 'MarkerFaceColor', col, 'MarkerSize', 6, ...
            'CapSize', 4);
        leg_handles(end+1) = h; %#ok<AGROW>
        leg_labels{end+1}  = int_name; %#ok<AGROW>
    end

    % Mark PETM interval boundaries
    yline(petm_bottom_m, '--k', 'PETM onset', ...
        'LabelHorizontalAlignment', 'left', 'FontSize', 8);
    yline(petm_top_m, '--k', 'PETM top', ...
        'LabelHorizontalAlignment', 'left', 'FontSize', 8);

    set(gca, 'YDir', 'reverse');
    xlabel('SST (°C)');
    ylabel('Depth (m)');
    title(sp);
    if ~isempty(leg_handles)
        legend(leg_handles, leg_labels, 'Location', 'best');
    end
    grid on;
    box on;
end

sgtitle('BAYMAG SST predictions (median ± 1\sigma, p16-p84)');

% Save figure
saveas(gcf, 'Babila_SST_plot.png');
fprintf('Plot saved to Babila_SST_plot.png\n');
