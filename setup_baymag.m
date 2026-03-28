% setup_baymag.m
% Run this once in MATLAB from the BAYMAG directory to install MatlabStan,
% configure CmdStan, and save the necessary paths.
%
% Prerequisites: CmdStan must already be installed. If not, run:
%   bash setup_stan.sh
% from a terminal in this directory first.

fprintf('=== BAYMAG Setup ===\n\n');

%% 1. Find CmdStan in ~/.cmdstan/
cmdstan_base = fullfile(getenv('HOME'), '.cmdstan');
d = dir(fullfile(cmdstan_base, 'cmdstan-*'));
dirs = d([d.isdir]);
if isempty(dirs)
    error(['CmdStan not found in %s.\n' ...
           'Please run the following from a terminal first:\n' ...
           '  bash setup_stan.sh\n'], cmdstan_base);
end
% Pick the highest version (last alphabetically)
[~, idx] = sort({dirs.name});
cmdstan_dir = fullfile(cmdstan_base, dirs(idx(end)).name);
fprintf('Found CmdStan: %s\n', cmdstan_dir);

%% 2. Download MatlabProcessManager if needed
pm_dir = fullfile(getenv('HOME'), 'MatlabProcessManager');
if ~exist(pm_dir, 'dir')
    fprintf('Downloading MatlabProcessManager...\n');
    ret = system(['wget -q "https://github.com/brian-lau/MatlabProcessManager/archive/refs/heads/master.tar.gz"' ...
                  ' -O /tmp/MatlabProcessManager.tar.gz']);
    if ret ~= 0, error('Failed to download MatlabProcessManager.'); end
    system(['tar -xzf /tmp/MatlabProcessManager.tar.gz -C ' getenv('HOME')]);
    movefile(fullfile(getenv('HOME'), 'MatlabProcessManager-master'), pm_dir);
    delete('/tmp/MatlabProcessManager.tar.gz');
    fprintf('  Installed at: %s\n', pm_dir);
else
    fprintf('MatlabProcessManager already at: %s\n', pm_dir);
end

%% 3. Download MatlabStan if needed
ms_dir = fullfile(getenv('HOME'), 'MatlabStan');
if ~exist(ms_dir, 'dir')
    fprintf('Downloading MatlabStan v2.15.1.0...\n');
    ret = system(['wget -q "https://github.com/brian-lau/MatlabStan/archive/refs/tags/v2.15.1.0.tar.gz"' ...
                  ' -O /tmp/MatlabStan.tar.gz']);
    if ret ~= 0, error('Failed to download MatlabStan.'); end
    system(['tar -xzf /tmp/MatlabStan.tar.gz -C ' getenv('HOME')]);
    movefile(fullfile(getenv('HOME'), 'MatlabStan-2.15.1.0'), ms_dir);
    delete('/tmp/MatlabStan.tar.gz');
    fprintf('  Installed at: %s\n', ms_dir);
else
    fprintf('MatlabStan already at: %s\n', ms_dir);
end

%% 4. Patch StanModel.m for newer CmdStan (fixes "Having a problem getting stan version")
stan_model_path = fullfile(ms_dir, 'StanModel.m');
fid = fopen(stan_model_path, 'r');
content = fread(fid, '*char')';
fclose(fid);

if ~contains(content, 'patched by setup_baymag.m')
    fprintf('Patching StanModel.m for newer CmdStan compatibility...\n');
    parts = strsplit(cmdstan_dir, filesep);
    cmdstan_name = parts{end};
    ver_str = strrep(cmdstan_name, 'cmdstan-', '');
    content = strrep(content, ...
        'ver = self.stan_version();', ...
        ['%ver = self.stan_version(); % patched by setup_baymag.m' newline ...
         '               ver = ''' ver_str ''';']);
    fid = fopen(stan_model_path, 'w');
    fwrite(fid, content);
    fclose(fid);
    fprintf('  StanModel.m patched (version hardcoded to %s).\n', ver_str);
else
    fprintf('StanModel.m already patched.\n');
end

%% 5. Write stan_home.m to point to CmdStan
stan_home_path = fullfile(ms_dir, '+mstan', 'stan_home.m');
fid = fopen(stan_home_path, 'w');
fprintf(fid, '%% Auto-configured by setup_baymag.m - do not edit manually\n');
fprintf(fid, 'function d = stan_home()\n\n');
fprintf(fid, 'd = ''%s'';\n', cmdstan_dir);
fclose(fid);
fprintf('Configured stan_home.m -> %s\n', cmdstan_dir);

%% 6. Add paths and save
baymag_dir = fileparts(mfilename('fullpath'));
addpath(baymag_dir);
addpath(ms_dir);
addpath(pm_dir);

% Save to user's MATLAB folder (avoids permission errors on system pathdef.m)
user_matlab_dir = fullfile(getenv('HOME'), 'Documents', 'MATLAB');
if ~exist(user_matlab_dir, 'dir')
    mkdir(user_matlab_dir);
end
pathdef_out = fullfile(user_matlab_dir, 'pathdef.m');
savepath(pathdef_out);
fprintf('MATLAB paths saved to: %s\n', pathdef_out);

%% 7. Fix MATLAB libstdc++ conflict (MATLAB's bundled libstdc++ is older than
%     what compiled Stan binaries require; prepend system lib path in startup.m)
[ret, sys_lib_dir] = system('/sbin/ldconfig -p 2>/dev/null | grep "libstdc++.so.6 " | grep x86-64 | head -1 | awk ''{print $NF}'' | xargs dirname');
sys_lib_dir = strtrim(sys_lib_dir);
if ret ~= 0 || isempty(sys_lib_dir)
    % Fallback common paths
    candidates = {'/lib/x86_64-linux-gnu', '/usr/lib/x86_64-linux-gnu', '/usr/lib64'};
    sys_lib_dir = '';
    for k = 1:numel(candidates)
        if exist(fullfile(candidates{k}, 'libstdc++.so.6'), 'file')
            sys_lib_dir = candidates{k};
            break;
        end
    end
end

if ~isempty(sys_lib_dir)
    startup_path = fullfile(user_matlab_dir, 'startup.m');
    fix_tag = '% baymag libstdc++ fix';
    startup_content = '';
    if exist(startup_path, 'file')
        fid = fopen(startup_path, 'r');
        startup_content = fread(fid, '*char')';
        fclose(fid);
    end
    if ~contains(startup_content, fix_tag)
        fid = fopen(startup_path, 'a');
        fprintf(fid, '\n%s\n', fix_tag);
        fprintf(fid, 'ld = getenv(''LD_LIBRARY_PATH'');\n');
        fprintf(fid, 'if ~contains(ld, ''%s'')\n', sys_lib_dir);
        fprintf(fid, '    setenv(''LD_LIBRARY_PATH'', [''%s:'' ld]);\n', sys_lib_dir);
        fprintf(fid, 'end\n');
        fclose(fid);
        fprintf('startup.m updated to fix libstdc++ conflict.\n');
    else
        fprintf('startup.m already has libstdc++ fix.\n');
    end
    % Apply immediately for this session
    ld = getenv('LD_LIBRARY_PATH');
    if ~contains(ld, sys_lib_dir)
        setenv('LD_LIBRARY_PATH', [sys_lib_dir ':' ld]);
        fprintf('LD_LIBRARY_PATH updated for this session: %s\n', sys_lib_dir);
    end
else
    fprintf('Warning: could not locate system libstdc++. If Stan fails with libstdc++ errors,\n');
    fprintf('manually add your system lib directory to LD_LIBRARY_PATH before running MATLAB.\n');
end

fprintf('\n=== Setup complete ===\n');
fprintf('You can now run baymag_predict.m to predict SST from Mg/Ca.\n');
fprintf('See Babila_mgca_test.m for a worked example.\n\n');
