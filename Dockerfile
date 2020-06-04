FROM centos:latest
LABEL description="Builds ufs-community/ufs-mrweather-app in one step."
LABEL author="lgilliam@innovim.com"

# This was required on a fresh Ubuntu 18.04 host on AWS
ENV SKIP_YUM_GPGCHECK --nogpgcheck
#ENV SKIP_YUM_GPGCHECK '' # Use this instead for proper security if you can

# Install tools and build dependencies
RUN yum update -y
RUN yum install $SKIP_YUM_GPGCHECK -y gcc-gfortran gcc-c++
RUN yum install $SKIP_YUM_GPGCHECK -y wget
RUN yum install $SKIP_YUM_GPGCHECK -y git
RUN yum install $SKIP_YUM_GPGCHECK -y make
RUN yum install $SKIP_YUM_GPGCHECK -y openssl-devel
RUN yum install $SKIP_YUM_GPGCHECK -y patch
RUN yum install $SKIP_YUM_GPGCHECK -y python2
RUN alternatives --set python /usr/bin/python2
RUN yum install $SKIP_YUM_GPGCHECK -y libxml2-2.9.7


RUN mkdir /usr/local/ufs-release-v1

ENV CC=gcc
ENV CXX=g++
ENV FC=gfortran

RUN mkdir -p /usr/local/ufs-release-v1/src

# Build NCEPLIBS-external
WORKDIR /usr/local/ufs-release-v1/src
RUN git clone -b ufs-v1.0.0 --recursive https://github.com/NOAA-EMC/NCEPLIBS-external
WORKDIR /usr/local/ufs-release-v1/src/NCEPLIBS-external/cmake-src
RUN ./bootstrap --prefix=/usr/local/ufs-release-v1
RUN make
RUN make install
RUN mkdir /usr/local/ufs-release-v1/src/NCEPLIBS-external/build
WORKDIR /usr/local/ufs-release-v1/src/NCEPLIBS-external/build
RUN /usr/local/ufs-release-v1/bin/cmake -DCMAKE_INSTALL_PREFIX=/usr/local/ufs-release-v1 .. 2>&1 | tee log.cmake
RUN make -j8 2>&1 | tee log.make

# Build NCEPLIBS
WORKDIR /usr/local/ufs-release-v1/src
RUN git clone -b ufs-v1.0.0 --recursive https://github.com/NOAA-EMC/NCEPLIBS
RUN mkdir /usr/local/ufs-release-v1/src/NCEPLIBS/build
WORKDIR /usr/local/ufs-release-v1/src/NCEPLIBS/build
RUN /usr/local/ufs-release-v1/bin/cmake -DCMAKE_INSTALL_PREFIX=/usr/local/ufs-release-v1 -DEXTERNAL_LIBS_DIR=/usr/local/ufs-release-v1 .. 2>&1 | tee log.cmake
RUN make -j8 2>&1 | tee log.make
RUN make install 2>&1 | tee log.install

# specify lib locations a la /usr/local/ufs-release-v1/bin/setenv_nceplibs.sh
ENV PATH "/usr/local/ufs-release-v1/bin:${PATH}"
ENV LD_LIBRARY_PATH "/usr/local/ufs-release-v1/lib64:${LD_LIBRARY_PATH}"
ENV ESMFMKFILE /usr/local/ufs-release-v1/lib64/esmf.mk
ENV NETCDF=/usr/local/ufs-release-v1
ENV NCEPLIBS_DIR /usr/local/ufs-release-v1
ENV NEMSIO_INC /usr/local/ufs-release-v1/include
ENV NEMSIO_LIB /usr/local/ufs-release-v1/lib/libnemsio_v2.3.0.a
ENV BACIO_LIB4 /usr/local/ufs-release-v1/lib/libbacio_v2.2.0_4.a
ENV SP_LIBd /usr/local/ufs-release-v1/lib/libsp_v2.1.0_d.a
ENV W3EMC_LIBd /usr/local/ufs-release-v1/lib/libw3emc_v2.5.0_d.a
ENV W3NCO_LIBd /usr/local/ufs-release-v1/lib/libw3nco_v2.1.0_d.a

# Mr. Weather Setup
WORKDIR /
RUN git clone https://github.com/ufs-community/ufs-mrweather-app.git -b ufs-v1.0.0 my_ufs_sandbox
WORKDIR /my_ufs_sandbox
RUN ./manage_externals/checkout_externals
RUN mkdir /scratch
ENV SCRATCH /scratch
RUN mkdir -p $SCRATCH/inputs/ufs_inputdata
ENV UFS_SCRATCH $SCRATCH
ENV UFS_INPUT $SCRATCH/inputs
ENV PROJECT MrWeather


WORKDIR /my_ufs_sandbox/cime/scripts
ENV USER root


# Put current hostname in the cime config
# needs to happen in the same RUN line as create_newcase because hostname changes between docker layers
RUN sed -i -e "s/ something\.matching\.your\.machine\.hostname /$(hostname)/" \
    /my_ufs_sandbox/cime/config/ufs/machines/config_machines.xml \
    && ./create_newcase --case DORIAN_C96_GFSv15p2 --compset GFSv15p2 --res C96 --workflow ufs-mrweather

# Create a case and set up the run
WORKDIR /my_ufs_sandbox/cime/scripts/DORIAN_C96_GFSv15p2
RUN ./case.setup
RUN ./case.build
RUN ./xmlchange STOP_OPTION=nhours,STOP_N=48
RUN ./xmlchange JOB_WALLCLOCK_TIME=00:45:00
RUN ./xmlchange USER_REQUESTED_WALLTIME=00:45:00

# This will be executed by default when you do: docker run
CMD ./case.submit
