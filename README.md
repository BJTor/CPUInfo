# CPUInfo
_MATLAB utility for returning information about your processor and memory._

[![Open in MATLAB Online](https://www.mathworks.com/images/responsive/global/open-in-matlab-online.svg)](https://matlab.mathworks.com/open/github/v1?repo=BJTor/CPUInfo&file=cpuinfo.m)
[![View CPU Info on File Exchange](https://www.mathworks.com/matlabcentral/images/matlab-file-exchange.svg)](https://www.mathworks.com/matlabcentral/fileexchange/33155-cpu-info)

This function reads various bits of information about the CPU and operating
system, including:
 * CPU name
 * CPU clock speed
 * CPU Cache size (L2, in bytes)
 * Total system memory (in bytes)
 * Number of CPU sockets
 * Number of physical CPU cores
 * Operating system name & version

These are provided by /proc/cpu (Unix), sysctl and sw_vers (Mac) or WMIC (Windows).

Requires MATLAB R2016b or above.
