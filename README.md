# FPCFiber
Lightwight cross platform fiber implementation intendet to be used by https://github.com/Warfley/STAX to move a lot of the platform dependent code into this repository and clean up the main repo.

Can also be used as standalone library to implement custom coroutines.

The current implementation for Unix systems requires changes to the RTL.
To use this rebuild FPC from source with the changes in fpc.patch.
You can apply these changes e.g. via `git apply` before calling make to build the FPC and RTL.
