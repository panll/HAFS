#!/bin/sh

set -xe

TOTAL_TASKS=${TOTAL_TASKS:-4}
NCTSK=${NCTSK:-4}
NCNODE=${NCNODE:-24}
OMP_NUM_THREADS=${OMP_NUM_THREADS:-6}
OMP_STACKSIZE=${OMP_STACKSIZE:-2048m}
KMP_STACKSIZE=${KMP_STACKSIZE:-1024m}
APRUNS=${APRUNS:-"aprun -b -j1 -n1 -N1 -d1 -cc depth"}
APRUNF=${APRUNF:-"aprun -b -j1 -n${TOTAL_TASKS} -N${NCTSK} -d${OMP_NUM_THREADS} -cc depth cfp"}
APRUNC=${APRUNC:-"aprun -b -j1 -n${TOTAL_TASKS} -N${NCTSK} -d${OMP_NUM_THREADS} -cc depth"}
export APRUN=time

CDATE=${CDATE:-${YMDH}}
CASE=${CASE:-C768}
CRES=`echo $CASE | cut -c 2-`
gtype=${GTYPE:-regional}           # grid type = uniform, stretch, nest, or stand alone regional

HOMEhafs=${HOMEhafs:-/gpfs/hps3/emc/hwrf/noscrub/${USER}/save/HAFS}
WORKhafs=${WORKhafs:-/gpfs/hps3/ptmp/${USER}/${SUBEXPT}/${CDATE}/${STORMID}}
COMhafs=${COMhafs:-${COMOUT}}
USHhafs=${USHhafs:-${HOMEhafs}/ush}
PARMhafs=${PARMhafs:-${HOMEhafs}/parm}
EXEChafs=${EXEChafs:-${HOMEhafs}/exec}
FIXhafs=${FIXhafs:-${HOMEhafs}/fix}

FIXam=${FIXhafs}/fix_am
FIXorog=${FIXhafs}/fix_orog
FIXfv3=${FIXhafs}/fix_fv3

export script_dir=${USHhafs}
export exec_dir=${EXEChafs}
export out_dir=${OUTDIR:-${WORKhafs}/intercom/grid}
export DATA=${DATA:-${WORKhafs}/grid}

export MAKEHGRIDEXEC=${EXEChafs}/hafs_make_hgrid.x
export MAKEMOSAICEXEC=${EXEChafs}/hafs_make_solo_mosaic.x
export FILTERTOPOEXEC=${EXEChafs}/hafs_filter_topo.x
export FREGRIDEXEC=${EXEChafs}/hafs_fregrid.x
export OROGEXEC=${EXEChafs}/hafs_orog.x
export SHAVEEXEC=${EXEChafs}/hafs_shave.x

export MAKEGRIDSSH=${USHhafs}/hafs_make_grid.sh
export MAKEOROGSSH=${USHhafs}/hafs_make_orog.sh
export FILTERTOPOSSH=${USHhafs}/hafs_filter_topo.sh

machine=${WHERE_AM_I:-wcoss_cray} # platforms: wcoss_cray, wcoss_dell_p3, theia, jet

date

export gridfixdir=${gridfixdir:-'/let/hafs_grid/generate/grid'}
# If gridfixdir is specified and exists, use the grid fix files directly
if [ -d $gridfixdir ]; then
  echo "$gridfixdir is specified and exists."
  echo "Copy the grid fix files directly."
  cp -rp $gridfixdir/* ${out_dir}/
  ls ${out_dir}
  exit 0
fi

# Otherwise, generate grid according to the following parameters
#----------------------------------------------------------------
if [ $gtype = uniform ];  then
  echo "creating uniform ICs"
elif [ $gtype = stretch ]; then
  export stretch_fac=${stretch_fac:-1.5}        # Stretching factor for the grid
  export target_lon=${target_lon:--97.5}      # center longitude of the highest resolution tile
  export target_lat=${target_lat:-35.5}       # center latitude of the highest resolution tile
  echo "creating stretched grid"
elif [ $gtype = nest ] || [ $gtype = regional ]; then
  export stretch_fac=${stretch_fac:-1.0001}     # Stretching factor for the grid
  export target_lon=${target_lon:--62.0}      # center longitude of the highest resolution tile
  export target_lat=${target_lat:-22.0}       # center latitude of the highest resolution tile
  # Need for grid types: nest and regional
  export refine_ratio=${refine_ratio:-4}      # Specify the refinement ratio for nest grid
  export istart_nest=${istart_nest:-46}
  export jstart_nest=${jstart_nest:-238}
  export iend_nest=${iend_nest:-1485}
  export jend_nest=${jend_nest:-1287}
  export halo=${halo:-3}                      # halo size to be used in the atmosphere cubic sphere model for the grid tile.
  export halop1=${halop1:-4}                  # halo size that will be used for the orography and grid tile in chgres
  export halo0=${halo0:-0}                    # no halo, used to shave the filtered orography for use in the model
  if [ $gtype = nest ];then
   echo "creating nested grid"
  else
   echo "creating regional grid"
  fi
else
  echo "Error: please specify grid type with 'gtype' as uniform, stretch, nest or regional"
  exit 1
fi

#----------------------------------------------------------------
#filter_topo parameters. C192->50km, C384->25km, C768->13km, C1152->8.5km, C3072->3.2km
if [ $CRES -eq 48 ]; then 
 export cd4=0.12;  export max_slope=0.12; export n_del2_weak=4;   export peak_fac=1.1  
elif [ $CRES -eq 96 ]; then 
 export cd4=0.12;  export max_slope=0.12; export n_del2_weak=8;   export peak_fac=1.1  
elif [ $CRES -eq 192 ]; then 
 export cd4=0.15;  export max_slope=0.12; export n_del2_weak=12;  export peak_fac=1.05  
elif [ $CRES -eq 384 ]; then 
 export cd4=0.15;  export max_slope=0.12; export n_del2_weak=12;  export peak_fac=1.0  
elif [ $CRES -eq 768 ]; then 
 export cd4=0.15;  export max_slope=0.12; export n_del2_weak=16;   export peak_fac=1.0  
elif [ $CRES -eq 1152 ]; then 
 export cd4=0.15;  export max_slope=0.16; export n_del2_weak=20;   export peak_fac=1.0  
elif [ $CRES -eq 3072 ]; then 
 export cd4=0.15;  export max_slope=0.30; export n_del2_weak=24;   export peak_fac=1.0  
else
 echo "grid C$CRES not supported, exit"
 exit 1
fi

date
#----------------------------------------------------------------
# Make grid and orography

export grid_dir=$DATA/grid
export orog_dir=$DATA/orog
if [ $gtype = uniform ] || [ $gtype = stretch ] ;  then
  export filter_dir=$DATA/filter_topo
elif [ $gtype = nest ] || [ $gtype = regional ] ;  then
  export filter_dir=$DATA/filter_topo
  export filter_dir=$orog_dir   # nested grid topography will be filtered online
fi
mkdir -p $grid_dir $orog_dir $filter_dir

if [ $gtype = uniform ] || [ $gtype = stretch ] ;  then
  export ntiles=6
  date
  echo "............ execute $MAKEGRIDSSH ................."
  if [ $gtype = uniform ];  then
    ${APRUNS} $MAKEGRIDSSH $CRES $grid_dir $script_dir
  elif [ $gtype = stretch ]; then
    ${APRUNS} $MAKEGRIDSSH $CRES $grid_dir $stretch_fac $target_lon $target_lat $script_dir
  fi
  date
  echo "............ execute $MAKEOROGSSH ................."
  # Run multiple tiles simulatneously for the orography

  echo "${APRUNO} $MAKEOROGSSH $CRES 1 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 2 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 3 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 4 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 5 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 6 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
if [ "$machine" = theia ] || [ "$machine" = jet ]; then
  echo 'wait' >> orog.file1
fi
  chmod u+x $DATA/orog.file1
  #aprun -j 1 -n 4 -N 4 -d 6 -cc depth cfp $DATA/orog.file1
  ${APRUNF} $DATA/orog.file1
  wait
  #rm $DATA/orog.file1
  date
  echo "............ execute $FILTERTOPOSSH .............."
  $FILTERTOPOSSH $CRES $grid_dir $orog_dir $filter_dir $cd4 $peak_fac $max_slope $n_del2_weak $script_dir $gtype
  echo "Grid and orography files are now prepared"
elif [ $gtype = nest ]; then
  export ntiles=7
  date
  echo "............ execute $MAKEGRIDSSH ................."
  ${APRUNS} $MAKEGRIDSSH $CRES $grid_dir $stretch_fac $target_lon $target_lat $refine_ratio $istart_nest $jstart_nest $iend_nest $jend_nest $halo $script_dir
  date
  echo "............ execute $MAKEOROGSSH ................."
  # Run multiple tiles simulatneously for the orography
  echo "${APRUNO} $MAKEOROGSSH $CRES 1 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 2 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 3 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 4 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 5 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 6 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 7 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
if [ "$machine" = theia ] || [ "$machine" = jet ]; then
  echo 'wait' >> orog.file1
fi
  chmod u+x $DATA/orog.file1
  #aprun -j 1 -n 4 -N 4 -d 6 -cc depth cfp $DATA/orog.file1
  ${APRUNF} $DATA/orog.file1
  wait
  #rm $DATA/orog.file1
  date
  echo "Grid and orography files are now prepared"
elif [ $gtype = regional ]; then
  # We are now creating only 1 tile and it is tile 7
  export ntiles=1
  tile=7

  # number of parent points
  nptsx=`expr $iend_nest - $istart_nest + 1`
  nptsy=`expr $jend_nest - $jstart_nest + 1`
  # number of compute grid points
  npts_cgx=`expr $nptsx  \* $refine_ratio / 2`
  npts_cgy=`expr $nptsy  \* $refine_ratio / 2`
 
  # figure out how many columns/rows to add in each direction so we have at least 5 halo points
  # for make_hgrid and the orography program
  index=0
  add_subtract_value=0
  while (test "$index" -le "0")
  do
    add_subtract_value=`expr $add_subtract_value + 1`
    iend_nest_halo=`expr $iend_nest + $add_subtract_value`
    istart_nest_halo=`expr $istart_nest - $add_subtract_value`
    newpoints_i=`expr $iend_nest_halo - $istart_nest_halo + 1`
    newpoints_cg_i=`expr $newpoints_i  \* $refine_ratio / 2`
    diff=`expr $newpoints_cg_i - $npts_cgx`
    if [ $diff -ge 10 ]; then 
      index=`expr $index + 1`
    fi
  done
  jend_nest_halo=`expr $jend_nest + $add_subtract_value`
  jstart_nest_halo=`expr $jstart_nest - $add_subtract_value`

  echo "================================================================================== "
  echo "For refine_ratio= $refine_ratio" 
  echo " iend_nest= $iend_nest iend_nest_halo= $iend_nest_halo istart_nest= $istart_nest istart_nest_halo= $istart_nest_halo"
  echo " jend_nest= $jend_nest jend_nest_halo= $jend_nest_halo jstart_nest= $jstart_nest jstart_nest_halo= $jstart_nest_halo"
  echo "================================================================================== "

  echo "............ execute $MAKEGRIDSSH ................."
  ${APRUNS} $MAKEGRIDSSH $CRES $grid_dir $stretch_fac $target_lon $target_lat $refine_ratio $istart_nest_halo $jstart_nest_halo $iend_nest_halo $jend_nest_halo $halo $script_dir

  date
  echo "............ execute $MAKEOROGSSH ................."
  #echo "$MAKEOROGSSH $CRES 7 $grid_dir $orog_dir $script_dir $FIXorog $DATA " >>$DATA/orog.file1
  echo "${APRUNO} $MAKEOROGSSH $CRES 7 $grid_dir $orog_dir $script_dir $FIXorog $DATA ${BACKGROUND}" >>$DATA/orog.file1
if [ "$machine" = theia ] || [ "$machine" = jet ]; then
  echo 'wait' >> orog.file1
fi
  chmod u+x $DATA/orog.file1
  #aprun -j 1 -n 4 -N 4 -d 6 -cc depth cfp $DATA/orog.file1
  ${APRUNF} $DATA/orog.file1
  wait
  #rm $DATA/orog.file1

  date
  echo "............ execute $FILTERTOPOSSH .............."
  ${APRUNS} $FILTERTOPOSSH $CRES $grid_dir $orog_dir $filter_dir $cd4 $peak_fac $max_slope $n_del2_weak $script_dir $gtype

  echo "............ execute shave to reduce grid and orography files to required compute size .............."
  cd $filter_dir
  # shave the orography file and then the grid file, the echo creates the input file that contains the number of required points
  # in x and y and the input and output file names.This first run of shave uses a halo of 4. This is necessary so that chgres will create BC's 
  # with 4 rows/columns which is necessary for pt.
  echo $npts_cgx $npts_cgy $halop1 \'$filter_dir/oro.${CASE}.tile${tile}.nc\' \'$filter_dir/oro.${CASE}.tile${tile}.shave.nc\' >input.shave.orog
  echo $npts_cgx $npts_cgy $halop1 \'$filter_dir/${CASE}_grid.tile${tile}.nc\' \'$filter_dir/${CASE}_grid.tile${tile}.shave.nc\' >input.shave.grid

  #aprun -n 1 -N 1 -j 1 -d 1 -cc depth $exec_dir/shave.x <input.shave.orog
  #aprun -n 1 -N 1 -j 1 -d 1 -cc depth $exec_dir/shave.x <input.shave.grid
  ${APRUNS} ${SHAVEEXEC} < input.shave.orog
  ${APRUNS} ${SHAVEEXEC} < input.shave.grid

  echo "Grid and orography files are now prepared"

fi
#----------------------------------------------------------------

if [ $gtype = regional ]; then
  cp $filter_dir/oro.${CASE}.tile${tile}.shave.nc $out_dir/${CASE}_oro_data.tile${tile}.halo${halop1}.nc
  cp $filter_dir/${CASE}_grid.tile${tile}.shave.nc  $out_dir/${CASE}_grid.tile${tile}.halo${halop1}.nc

  # Now shave the orography file with no halo and then the grid file with a halo of 3. This is necessary for running the model.
  echo $npts_cgx $npts_cgy $halo0 \'$filter_dir/oro.${CASE}.tile${tile}.nc\' \'$filter_dir/oro.${CASE}.tile${tile}.shave.nc\' >input.shave.orog.halo$halo0
  echo $npts_cgx $npts_cgy $halo \'$filter_dir/${CASE}_grid.tile${tile}.nc\' \'$filter_dir/${CASE}_grid.tile${tile}.shave.nc\' >input.shave.grid.halo$halo
  ${APRUNS} ${SHAVEEXEC} < input.shave.orog.halo$halo0
  ${APRUNS} ${SHAVEEXEC} < input.shave.grid.halo$halo

  # Copy the shaved files with the halo of 3 required for the model run
  cp $filter_dir/oro.${CASE}.tile${tile}.shave.nc $out_dir/${CASE}_oro_data.tile${tile}.halo${halo0}.nc
  cp $filter_dir/${CASE}_grid.tile${tile}.shave.nc  $out_dir/${CASE}_grid.tile${tile}.halo${halo}.nc
else
  tile=1
  while [ $tile -le $ntiles ]; do
    cp $filter_dir/oro.${CASE}.tile${tile}.nc $out_dir/${CASE}_oro_data.tile${tile}.nc
    cp $grid_dir/${CASE}_grid.tile${tile}.nc  $out_dir/${CASE}_grid.tile${tile}.nc
    tile=`expr $tile + 1 `
  done
fi

#cp $filter_dir/${CASE}_mosaic.nc $out_dir/grid_spec.nc
#cp $filter_dir/${CASE}_mosaic.nc $out_dir/${CASE}_mosaic.nc
cp $grid_dir/${CASE}_mosaic.nc $out_dir/${CASE}_mosaic.nc

exit
