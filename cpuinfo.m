function info = cpuinfo()
%CPUINFO  read CPU configuration
%
%   info = CPUINFO() returns a structure containing various bits of
%   information about the CPU and operating system as provided by /proc/cpu
%   (Unix), sysctl (Mac) or WMIC (Windows). This information includes:
%     * CPU name
%     * CPU clock speed
%     * CPU Cache size (L2)
%     * Number of physical CPU cores
%     * Operating system name & version
%
%   See also: COMPUTER, ISUNIX, ISMAC

%   Author: Ben Tordoff
%   Copyright 2011-2021 The MathWorks, Inc.

if isunix
    if ismac
        info = cpuInfoMac();
    else
        info = cpuInfoUnix();
    end
else
    info = cpuInfoWindows();
end


%-------------------------------------------------------------------------%
function info = cpuInfoWindows()
sysInfo = callWMIC( 'cpu' );
osInfo = callWMIC( 'os' );

info = struct( ...
    'Name', sysInfo.Name, ...
    'Clock', [sysInfo.MaxClockSpeed,' MHz'], ...
    'Cache', [sysInfo.L2CacheSize,' KB'], ...
    'NumProcessors', str2double( sysInfo.NumberOfCores ), ...
    'OSType', 'Windows', ...
    'OSVersion', osInfo.Caption );

%-------------------------------------------------------------------------%
function info = callWMIC( alias )
% Call the MS-DOS WMIC (Windows Management) command

% We move to a temporary folder since WMIC needs write access to the local
% folder
olddir = pwd();
cd( tempdir );
[~, sysinfo] = system(sprintf( 'wmic %s get /value', alias ));
cd( olddir );
fields = textscan( sysinfo, '%s', 'Delimiter', '\n' ); fields = fields{1};
fields( cellfun( 'isempty', fields ) ) = [];
% Each line has "field=value", so split them
values = cell( size( fields ) );
for ff=1:numel( fields )
    idx = find( fields{ff}=='=', 1, 'first' );
    if ~isempty( idx ) && idx>1
        values{ff} = strtrim( fields{ff}(idx+1:end) );
        fields{ff} = strtrim( fields{ff}(1:idx-1) );
    end
end

% Remove any duplicates (only occurs for dual-socket PC's and we will
% assume that all sockets have the same processors in them).
numResults = sum( strcmpi( fields, fields{1} ) );
if numResults>1
    % If we are counting cores, sum them.
    numCoresEntries = find( strcmpi( fields, 'NumberOfCores' ) );
    if ~isempty( numCoresEntries )
        cores = cellfun( @str2double, values(numCoresEntries) );
        values(numCoresEntries) = {num2str( sum( cores ) )};
    end
    % Now remove the duplicate results
    [fields,idx] = unique(fields,'first');
    values = values(idx);
end

% Convert to a structure
info = cell2struct( values, fields );

%-------------------------------------------------------------------------%
function info = cpuInfoMac()
machdep = callSysCtl( 'machdep.cpu' );
hw = callSysCtl( 'hw' );
info = struct( ...
    'Name', machdep.brand_string, ...
    'Clock', [num2str(str2double(hw.cpufrequency_max)/1e6),' MHz'], ...
    'Cache', [machdep.cache.size,' KB'], ...
    'NumProcessors', str2double( machdep.core_count ), ...
    'OSType', 'Mac OS/X', ...
    'OSVersion', getOSXVersion() );

%-------------------------------------------------------------------------%
function info = callSysCtl( namespace )
[~, infostr] = system( sprintf( 'sysctl -a %s', namespace ) );
% Remove the prefix
infostr = strrep( infostr, [namespace,'.'], '' );
% Now break into a structure
infostr = textscan( infostr, '%s', 'delimiter', '\n' );
infostr = infostr{1};
info = struct();
for ii=1:numel( infostr )
    colonIdx = find( infostr{ii}==':', 1, 'first' );
    if isempty( colonIdx ) || colonIdx==1 || colonIdx==length(infostr{ii})
        continue
    end
    prefix = infostr{ii}(1:colonIdx-1);
    value = strtrim(infostr{ii}(colonIdx+1:end));
    while ismember( '.', prefix )
        dotIndex = find( prefix=='.', 1, 'last' );
        suffix = prefix(dotIndex+1:end);
        prefix = prefix(1:dotIndex-1);
        value = struct( suffix, value );
    end
    info.(prefix) = value;
    
end

%-------------------------------------------------------------------------%
function vernum = getOSXVersion()
% Extract the OS version number from the system software version output.
[~, ver] = system('sw_vers');
vernum = regexp(ver, 'ProductVersion:\s([1234567890.]*)', 'tokens', 'once');
vernum = strtrim(vernum{1});

%-------------------------------------------------------------------------%
function info = cpuInfoUnix()
txt = readLinuxCPUInfo();
cpuinfo = parseLinuxCPUInfoText( txt );

txt = readLinuxOSInfo();
osinfo = parseLinuxOSInfoText( txt );

txt = readLinuxMemInfo();
meminfo = parseLinuxMemInfoText( txt );

% Merge the structures
info = cell2struct( [ ...
    struct2cell( cpuinfo )
    struct2cell( meminfo )
    struct2cell( osinfo )
    ], [ ...
    fieldnames( cpuinfo )
    fieldnames( meminfo )
    fieldnames( osinfo )
    ] );

%-------------------------------------------------------------------------%
function info = parseLinuxCPUInfoText( txt )
% Now parse the fields
lookup = {
    'model name',  'Name'
    'cpu Mhz',     'Clock'
    'cpu cores',   'CoresPerCPU'
    'physical id', 'NumCPUs'
    'cache size',  'Cache'
    };
info = struct( ...
    'Name', {''}, ...
    'Clock', {''}, ...
    'Cache', {''}, ...
    'CoresPerCPU', {[]}, ...
    'NumCPUs', {[]}, ...
    'TotalCores', {[]} );
for ii=1:numel( txt )
    if isempty( txt{ii} )
        continue;
    end
    % Look for the colon that separates the property name from the value
    colon = find( txt{ii}==':', 1, 'first' );
    if isempty( colon ) || colon==1 || colon==length( txt{ii} )
        continue;
    end
    fieldName = strtrim( txt{ii}(1:colon-1) );
    fieldValue = strtrim( txt{ii}(colon+1:end) );
    if isempty( fieldName ) || isempty( fieldValue )
        continue;
    end
    
    % Is it one of the fields we're interested in?
    idx = find( strcmpi( lookup(:,1), fieldName ) );
    if ~isempty( idx )
        newName = lookup{idx,2};
        info.(newName) = fieldValue;
    end
end

% Convert clock speed
info.Clock = [info.Clock, ' MHz'];

% Convert cache size
info.Cache = parseMemoryValue(info.Cache);

% The number of CPUs is the highest processor ID (+1 since zero-based)
info.NumCPUs = str2double(info.NumCPUs) + 1;
% Convert num cores
info.TotalCores = info.NumCPUs * str2double(info.CoresPerCPU);
info = rmfield(info, 'CoresPerCPU');

%-------------------------------------------------------------------------%
function info = parseLinuxOSInfoText( txt )
info = struct( ...
    'OSType', 'Linux', ...
    'OSVersion', '' );
% Find the string "linux version" then look for the bit up to the first
% bracket.
b = extractBetween(txt{1}, 'Linux version ', ' (');
info.OSVersion = b{1};


%-------------------------------------------------------------------------%
function info = parseLinuxMemInfoText( txt )
info = struct( ...
    'TotalMemory', parseMemoryValue(txt, 'MemTotal'), ...
    'FreeMemory', parseMemoryValue(txt, 'MemFree') );

%-------------------------------------------------------------------------%
function bytes = parseMemoryValue(txt, fieldname)
if nargin>1
    txt = txt{startsWith(txt, fieldname)};
end
if isempty(txt)
    bytes = 0;
else
    if endsWith(txt, 'kb', 'ignorecase', true)
        bytesMultiplier = 1024;
    elseif endsWith(txt, 'mb', 'ignorecase', true)
        bytesMultiplier = 1048576;
    elseif endsWith(txt, 'gb', 'ignorecase', true)
        bytesMultiplier = 1073741824;
    else
        bytesMultiplier = 1;
    end
    bytes = str2double(txt(txt>='0' & txt<='9')) * bytesMultiplier;
end


%-------------------------------------------------------------------------%
function txt = readLinuxCPUInfo()

fid = fopen( '/proc/cpuinfo', 'rt' );
if fid<0
    error( 'cpuinfo:BadPROCCPUInfo', 'Could not open /proc/cpuinfo for reading' );
end
cleanup = onCleanup( @() fclose( fid ) );

txt = textscan( fid, '%s', 'Delimiter', '\n' );
txt = txt{1};

%-------------------------------------------------------------------------%
function txt = readLinuxOSInfo()

fid = fopen( '/proc/version', 'rt' );
if fid<0
    error( 'cpuinfo:BadProcVersion', 'Could not open /proc/version for reading' );
end
cleanup = onCleanup( @() fclose( fid ) );

txt = textscan( fid, '%s', 'Delimiter', '\n' );
txt = txt{1};

%-------------------------------------------------------------------------%
function txt = readLinuxMemInfo()

fid = fopen( '/proc/meminfo', 'rt' );
if fid<0
    error( 'cpuinfo:BadProcVersion', 'Could not open /proc/version for reading' );
end
cleanup = onCleanup( @() fclose( fid ) );

txt = textscan( fid, '%s', 'Delimiter', '\n' );
txt = txt{1};
