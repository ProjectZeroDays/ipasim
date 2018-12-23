# We use image based on `microsoft/windowsservercore:ltsc2016` instead of
# `microsoft/windowsservercore:1803` because of this issue:
# https://github.com/moby/moby/issues/37283. The image we use is
# `microsoft/dotnet-framework:3.5-sdk-windowsservercore-ltsc2016`.
FROM microsoft/dotnet-framework@sha256:5637aa0d24af7d5d3c1726f1c280bbedf39cc8927364e5c3012d14b71c2ffce4
LABEL Name=ipasimulator Version=0.0.1

SHELL ["cmd", "/S", "/C"]
WORKDIR "c:/project"

# Install Chocolatey.
RUN powershell -c " \
    $env:chocolateyVersion = '0.10.11'; \
    $env:chocolateyUseWindowsCompression='false'; \
    Set-ExecutionPolicy Bypass -Scope Process -Force; \
    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')); \
    choco feature disable --name showDownloadProgress"

# Install CMake + Ninja.
RUN powershell -c " \
    choco install cmake --version 3.12.2 -y --installargs 'ADD_CMAKE_TO_PATH=User'; \
    choco install ninja --version 1.7.2 -y"

# Install LLVM + Clang.
RUN powershell -c "choco install llvm --version 7.0.0 -y"

# Install Node.js LTS
ADD https://nodejs.org/dist/v8.11.3/node-v8.11.3-x64.msi C:/temp/node-install.msi
RUN start /wait msiexec.exe /i C:/temp/node-install.msi /l*vx "C:/temp/MSI-node-install.log" /qn ADDLOCAL=ALL

# Install Visual Studio Build Tools.
# TODO: Don't do this, use LLVM-only toolchain instead when possible.
# For a list of components, see <https://docs.microsoft.com/en-us/visualstudio/
# install/workload-component-id-vs-build-tools?view=vs-2017>. For more
# information, see <https://blogs.msdn.microsoft.com/heaths/2018/06/14/
# no-container-image-for-build-tools-for-visual-studio-2017/> or <https://
# docs.microsoft.com/en-us/visualstudio/install/
# build-tools-container?view=vs-2017>.
COPY scripts/install_vs.cmd C:/temp/
# TODO: Use more specific URLs here.
ADD https://aka.ms/vscollect.exe C:/temp/collect.exe
ADD https://aka.ms/vs/15/release/channel C:/temp/visualstudio.chman
ADD https://aka.ms/vs/15/release/vs_buildtools.exe C:/temp/vs_buildtools.exe
RUN C:/temp/install_vs.cmd C:/temp/vs_buildtools.exe --quiet --wait --norestart --nocache \
    --installPath C:/BuildTools \
    --channelUri C:/temp/visualstudio.chman --installChannelUri C:/temp/visualstudio.chman \
    --add "Microsoft.VisualStudio.Workload.VCTools;includeRecommended;includeOptional"

# Install Python. It's needed to build LLVM and Clang.
RUN powershell -c "choco install python --version 3.7.0 -y"

# Install NuGet.
RUN powershell -c "choco install nuget.commandline --version 4.9.1 -y"

# Install C++/WinRT.
# TODO: Use the one from Windows SDK when we use some newer version of the SDK.
RUN powershell -c "nuget install cppwinrt -Version 2017.4.6.1 -OutputDirectory C:/packages"

# Start developer command prompt.
ENTRYPOINT C:/BuildTools/Common7/Tools/VsDevCmd.bat -arch=x86 -host_arch=x86 &&

CMD powershell -f scripts/build.ps1
