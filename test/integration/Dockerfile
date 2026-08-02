ARG MARIADB_IMAGE=mariadb:10.6@sha256:114d40be36852d0a019afd8458f7e1cc63fd300403b115b1f32e31130d5f671b
FROM ${MARIADB_IMAGE}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -c 'import ctypes, os; libc=ctypes.CDLL(None); assert all(op in os.supports_dir_fd for op in (os.open, os.stat, os.rename, os.unlink)); assert hasattr(libc, "renameat2")'
