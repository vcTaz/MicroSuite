## Verify
`shellcheck -S warning energy_proportionality/scripts/*.sh && python3 -m py_compile energy_proportionality/analysis/*.py`
Passing means the energy-proportionality experiment scripts have no shellcheck warnings or errors and the analysis scripts parse. The C++ gRPC services under `src/` are not covered: building them needs protoc 3, grpc_cpp_plugin, Intel MKL, FLANN and libmemcached, which are only set up inside the MicroSuite container (see README).
