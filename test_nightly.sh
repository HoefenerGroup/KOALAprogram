#!/bin/bash

#set -x

# enter your mail address:
list_mails=(erwin.schroedinger@nobel.org)

# enter your KOALA root path:
koala_root=/work/KOALA_TEST/koala_trunk_nightly

# use empty string if not needed:
licence_server=


# ======================================================================
# do not modify below here..
# ======================================================================
locdbg=false
# init this script:
SCRIPT_start_tim=`date +%s`
SCRIPT_name=test_nightly.sh

# export all variables:
export list_mails
export koala_root
export licence_server

export hostsnam=$(hostname)
export LOCKFILE="${koala_root}/test_nightly.lock"

export number_of_mails=${#list_mails[@]}

if "${locdbg}"
then # output the mails to be send:
     j=0
     while [ $j -lt ${number_of_mails} ]
     do echo "${j}. mail recipient: ${list_mails[$j]}"
        let j+=1
     done
fi

function print_walltime  { SCRIPT_start_tim=$1
                           SCRIPT_name=$2

                           SCRIPT_end_tim=`date +%s`

                           tim_walls=`echo "${SCRIPT_end_tim} - ${SCRIPT_start_tim}" | bc -l`
                           tim_wallm=`echo "${tim_walls} / 60 " | bc -l`
                           tim_wallh=`echo "${tim_wallm} / 60 " | bc -l`
                           tim_walld=`echo "${tim_wallh} / 24 " | bc -l`

                           echo " time ${SCRIPT_name} [s]: ${tim_walls}"
                           echo " time ${SCRIPT_name} [m]: ${tim_wallm}"
                           echo " time ${SCRIPT_name} [h]: ${tim_wallh}"
                           echo " time ${SCRIPT_name} [d]: ${tim_walld}"

                         }



function compile_it {  l_compile_success=false

                       compilelog=$1
                       shift
                       compileopt=$@

                       echo  >> ${LOCKFILE}
                       echo "attempting compilation: ./easy_compile.sh ${compileopt} > ${compilelog}" >> ${LOCKFILE}

                       gmake realclean
                       ./easy_compile.sh ${compileopt} > ${compilelog} 2>&1
                       easycompilereturncode=$?

                       # if compilation failed, then retry once:
                       if [ ${easycompilereturncode} -ne 0 ]
                       then if [ "${licence_server}" = "" ]
                            then # no licence server specified, just wait 5 seconds:
                                 echo
                                 echo "Compilation failed, retry compilation in 5 seconds..."
                                 echo
                                 sleep 5

                            else # wait until licence server is pingable again:
                                 echo
                                 echo "Compilation failed, retry compilation when server is pingable again..."
                                 echo
                                 while ! ping -c1 ${licence_server} 
                                 do sleep 5
                                 done
                                 #while ! ping -c1 ${licence_server} &>/dev/null; do :; done

                            fi

                            ./easy_compile.sh ${compileopt} > ${compilelog} 2>&1
                            easycompilereturncode=$?
                       fi

                       if [ ${easycompilereturncode} -eq 0 ]
                       then l_compile_success=true
                       else # copy the compilation output to the test run output so that is will put in the mail:
                            cp ${compilelog} ${pwdkoalatest}/test_em_nightly.out
                       fi
                    }

if [ $# -gt 1 ]
then echo "This script accepts only zero or 1 argument: -quick"
     #print_walltime ${SCRIPT_start_tim} ${SCRIPT_name}
     exit 1
fi

lquick=false
if [ $# -eq 1 ]
then if [ "$1" = "-quick" ]
     then lquick=true
     else echo "This script accepts only zero or 1 argument: -quick"
          #print_walltime ${SCRIPT_start_tim} ${SCRIPT_name}
          exit 1
     fi
fi

echo "lquick: ${lquick}"


cd ${koala_root}

if  [ -e ${LOCKFILE} ]
then echo "Found file: ${LOCKFILE}"
     echo "INTERRUPT SCRIPT!"

     j=0
     while [ $j -lt ${number_of_mails} ]
     do mail -s "KOALA NIGHTLY TEST: FOUND LOCK FILE" ${list_mails[$j]}  < ${LOCKFILE}
        let j+=1
     done

     exit 1
fi

echo "test_nightly.sh started: $(date)" > ${LOCKFILE}
echo >> ${LOCKFILE}

# now in ${pwdkoalaroot}:
pwdkoalaroot=$(pwd)

if [ "${pwdkoalaroot}" != "${koala_root}" ]
then echo "could not change to KOALA root directory"
     exit 1
fi

echo "updating koala:"
svn update 

#currentsvnrev=$(svnversion .)
currentsvnrev=$(svn info . | grep "^Revision: " | awk '{ print $2; }')
echo "current koala svn number: ${currentsvnrev}"

cd koala_suite
pwdkoala=$(pwd)

if [ "${pwdkoalaroot}/koala_suite" != "${pwdkoala}" ]
then echo "could not change to KOALA directory"
     exit 1
fi

  # now in ${pwdkoala}:
  echo "changed to koala directory"
  pwd

  echo "source the environment:"
  export qcdir=$(pwd)
  source $qcdir/qc_zsh.rc.sh
  source /opt/export/cluster/bin/set_INTEL_environment.sh

  # check the test directory:
  cd TEST
  export pwdkoalatest=$(pwd)
  
  if [ "${pwdkoalaroot}/koala_suite/TEST" != "${pwdkoalatest}" ]
  then echo "could not change to KOALA test directory"
       exit 1
  fi

  cd ${pwdkoala}
  # done.


  cd src
  pwdkoalasrc=$(pwd)
  
  if [ "${pwdkoalaroot}/koala_suite/src" != "${pwdkoalasrc}" ]
  then echo "could not change to KOALA src directory"
       exit 1
  fi


  cd ${pwdkoalasrc}
    # now in ${pwdkoalasrc}: =====================================================
    echo "changed to koala src directory"
    pwd

    compile_it easy_compile_gfortran.out -all f90=gfortran
    #gmake realclean
    #./easy_compile.sh -all f90=gfortran > easy_compile_gfortran.out 2>&1

    if "${l_compile_success}"
    then # run the tests
         cd ${pwdkoalatest}
           echo "changed to koala test directory"
           # now in ${pwdkoalatest}:
           pwd
       
           # first clean:
           find . -type d -name "TEST_RUN" -exec rm -rf {} \;
           find . -type f -name "TABLE.*" -exec rm -f {} \;
       
           # now run:
           cp $qcdir/src/timestamp.h test_em_nightly.out
           echo ""                            >> test_em_nightly.out
           ./test_em.sh regular.* developer.* >> test_em_nightly.out 2>&1
           killall --signal 9 --user localadmin -r _ex.test --verbose >> test_em_nightly.out 2>&1
       
           mailtitle=$(cat test_em.result)
       
    else # no binaries available:
         mailtitle="#   C O M P I L A T I O N    F A I L E D    #"
       
    fi

    echo "          ${mailtitle}" >> ${LOCKFILE}

    j=0
    while [ $j -lt ${number_of_mails} ]
    do mail -s "revision ${currentsvnrev} @${hostsnam}, GFORTRAN: ${mailtitle}" ${list_mails[$j]}  < ${pwdkoalatest}/test_em_nightly.out
       let j+=1
    done

  if "${lquick}"
  then echo "skip all other tests, because quick option is requested"

  else # run the remaining tests:

       cd ${pwdkoalasrc}
         # now in ${pwdkoalasrc}: =====================================================
         echo "changed to koala src directory"
         pwd

         export PCM=yes
         export LAPLACE=yes

         compile_it easy_compile_gfortran_special.out -all f90=gfortran
         #gmake realclean
         #./easy_compile.sh -all f90=gfortran > easy_compile_gfortran_special.out 2>&1


         if "${l_compile_success}"
         then # run the tests
              cd ${pwdkoalatest}
                echo "changed to koala test directory"
                # now in ${pwdkoalatest}:
                pwd
            
                # first clean:
                find . -type d -name "TEST_RUN" -exec rm -rf {} \;
                find . -type f -name "TABLE.*" -exec rm -f {} \;
            
                # now run:
                cp $qcdir/src/timestamp.h test_em_nightly.out
                echo ""           >> test_em_nightly.out
                ./test_em_mini.sh >> test_em_nightly.out 2>&1
            
                mailtitle=$(cat test_em.result)
            
         else # no binaries available:
              mailtitle="#   C O M P I L A T I O N    F A I L E D    #"
         fi

         echo "          ${mailtitle}" >> ${LOCKFILE}

         j=0
         while [ $j -lt ${number_of_mails} ]
         do mail -s "revision ${currentsvnrev} @${hostsnam}, GFORTRAN, SPECIAL: ${mailtitle}" ${list_mails[$j]}  < ${pwdkoalatest}/test_em_nightly.out
            let j+=1
         done

         unset PCM
         unset LAPLACE


       cd ${pwdkoalasrc}
         # now in ${pwdkoalasrc}: =====================================================
         echo "changed to koala src directory"
         pwd

         compile_it easy_compile_DEBUG.out -all
         #gmake realclean
         #./easy_compile.sh -all > easy_compile_DEBUG.out 2>&1


         if "${l_compile_success}"
         then # run the tests
              cd ${pwdkoalatest}
                echo "changed to koala test directory"
                # now in ${pwdkoalatest}:
                pwd
            
                # first clean:
                find . -type d -name "TEST_RUN" -exec rm -rf {} \;
                find . -type f -name "TABLE.*" -exec rm -f {} \;
            
                # now run:
                cp $qcdir/src/timestamp.h test_em_nightly.out
                echo ""                            >> test_em_nightly.out
                ./test_em.sh regular.* developer.* >> test_em_nightly.out 2>&1
                killall --signal 9 --user localadmin -r _ex.test --verbose >> test_em_nightly.out 2>&1
            
                mailtitle=$(cat test_em.result)
            
         else # no binaries available:
              mailtitle="#   C O M P I L A T I O N    F A I L E D    #"
            
         fi

         echo "          ${mailtitle}" >> ${LOCKFILE}

         j=0
         while [ $j -lt ${number_of_mails} ]
         do mail -s "revision ${currentsvnrev} @${hostsnam}, DEBUG: ${mailtitle}" ${list_mails[$j]}  < ${pwdkoalatest}/test_em_nightly.out
            let j+=1
         done


       cd ${pwdkoalasrc}
         # now in ${pwdkoalasrc}: =====================================================
         echo "changed to koala src directory"
         pwd

         export PCM=yes
         export LAPLACE=yes

         compile_it easy_compile_DEBUG.out -all
         #gmake realclean
         #./easy_compile.sh -all > easy_compile_DEBUG.out 2>&1

         if "${l_compile_success}"
         then # run the tests
              cd ${pwdkoalatest}
                echo "changed to koala test directory"
                # now in ${pwdkoalatest}:
                pwd
            
                # first clean:
                find . -type d -name "TEST_RUN" -exec rm -rf {} \;
                find . -type f -name "TABLE.*" -exec rm -f {} \;
            
                # now run:
                cp $qcdir/src/timestamp.h test_em_nightly.out
                echo ""           >> test_em_nightly.out
                ./test_em_mini.sh >> test_em_nightly.out 2>&1
            
                mailtitle=$(cat test_em.result)
            
         else # no binaries available:
              mailtitle="#   C O M P I L A T I O N    F A I L E D    #"
            
         fi

         echo "          ${mailtitle}" >> ${LOCKFILE}

         j=0
         while [ $j -lt ${number_of_mails} ]
         do mail -s "revision ${currentsvnrev} @${hostsnam}, DEBUG, SPECIAL: ${mailtitle}" ${list_mails[$j]}  < ${pwdkoalatest}/test_em_nightly.out
            let j+=1
         done

         unset PCM
         unset LAPLACE


       cd ${pwdkoalasrc}
         # now in ${pwdkoalasrc}: =====================================================
         echo "changed to koala src directory"
         pwd

         compile_it easy_compile_DEBUG_TIMING.out -all TIMING=yes
         #gmake realclean
         #./easy_compile.sh -all TIMING=yes > easy_compile_DEBUG_TIMING.out 2>&1


         if "${l_compile_success}"
         then # run the tests
              cd ${pwdkoalatest}
                echo "changed to koala test directory"
                # now in ${pwdkoalatest}:
                pwd
            
                # first clean:
                find . -type d -name "TEST_RUN" -exec rm -rf {} \;
                find . -type f -name "TABLE.*" -exec rm -f {} \;
            
                # now run:
                cp $qcdir/src/timestamp.h test_em_nightly.out
                echo ""                                   >> test_em_nightly.out
                ./test_em.sh regular.* developer.* long.* >> test_em_nightly.out 2>&1
                killall --signal 9 --user localadmin -r _ex.test --verbose >> test_em_nightly.out 2>&1
            
                mailtitle=$(cat test_em.result)
            
         else # no binaries available:
              mailtitle="#   C O M P I L A T I O N    F A I L E D    #"
            
         fi

         echo "          ${mailtitle}" >> ${LOCKFILE}

         j=0
         while [ $j -lt ${number_of_mails} ]
         do mail -s "revision ${currentsvnrev} @${hostsnam}, DEBUG: ${mailtitle}" ${list_mails[$j]}  < ${pwdkoalatest}/test_em_nightly.out
            let j+=1
         done


       cd ${pwdkoalasrc}
         # now in ${pwdkoalasrc}: =====================================================
         echo "changed to koala src directory"
         pwd

         compile_it easy_compile_RELEASE.out -all RELEASE=yes
         #gmake realclean
         #./easy_compile.sh -all RELEASE=yes > easy_compile_RELEASE.out 2>&1

         if "${l_compile_success}"
         then # run the tests
              cd ${pwdkoalatest}
                echo "changed to koala test directory"
                # now in ${pwdkoalatest}:
                pwd
            
                # first clean:
                find . -type d -name "TEST_RUN" -exec rm -rf {} \;
                find . -type f -name "TABLE.*" -exec rm -f {} \;
            
                # now run:
                cp $qcdir/src/timestamp.h test_em_nightly.out
                echo ""                                             >> test_em_nightly.out
                ./test_em.sh regular.* developer.* long.* release.* >> test_em_nightly.out 2>&1
                killall --signal 9 --user localadmin -r _ex.test --verbose >> test_em_nightly.out 2>&1
            
                mailtitle=$(cat test_em.result)
            
         else # no binaries available:
              mailtitle="#   C O M P I L A T I O N    F A I L E D    #"
            
         fi

         echo "          ${mailtitle}" >> ${LOCKFILE}

         j=0
         while [ $j -lt ${number_of_mails} ]
         do mail -s "revision ${currentsvnrev} @${hostsnam}: ${mailtitle}" ${list_mails[$j]}  < ${pwdkoalatest}/test_em_nightly.out
            let j+=1
         done
  fi # option '-quick'


# clean the test directory:
cd ${pwdkoalatest}
    find . -type d -name "TEST_RUN" -exec rm -rf {} \;
    find . -type f -name "TABLE.*"  -exec rm -f  {} \;

cd ${pwdkoalaroot}

# finally remove lock file:
cd ${koala_root}

echo >> ${LOCKFILE}
echo "test_nightly.sh ended: $(date)" >> ${LOCKFILE}

j=0
while [ $j -lt ${number_of_mails} ]
do mail -s "revision ${currentsvnrev} @${hostsnam}:   S U M M A R Y" ${list_mails[$j]} < ${LOCKFILE}
   let j+=1
done

rm ${LOCKFILE} > /dev/null 2> /dev/null

print_walltime ${SCRIPT_start_tim} ${SCRIPT_name}

echo    
echo  " ${SCRIPT_name}: all done"
echo    
echo    

