#!/bin/bash

# Simple deploy and undeploy scenarios for Jelastic Python

inherit default exceptor;
$PROGRAM unzip;

[[ -n "${WEBROOT}" ]] && [ ! -d "$WEBROOT" ] && mkdir -p ${WEBROOT};

[ -e "${MANAGE_CORE_PATH}/${COMPUTE_TYPE}"-deploy.lib ] && { include ${COMPUTE_TYPE}-deploy; }

function _setContext(){
        echo "You application just been deployed to wsgi context"
}

function getPackageName() {
    if [ -f "$package_url" ]; then
        package_name=$(basename "${package_url}")
        package_path=$(dirname "${package_url}")
    elif [[ "${package_url}" =~ file://* ]]; then
        package_name=$(basename "${package_url:7}")
        package_path=$(dirname "${package_url:7}")
        [ -f "${package_path}/${package_name}" ] || { writeJSONResponseErr "result=>4078" "message=>Error loading file from URL"; die -q; }
    else
        ensureFileCanBeDownloaded $package_url;
        $WGET --no-check-certificate --content-disposition --directory-prefix="$DOWNLOADS" $package_url >> $ACTIONS_LOG 2>&1 || { writeJSONResponseErr "result=>4078" "message=>Error loading file from URL"; die -q; }
        package_name="$(ls ${DOWNLOADS})";
        package_path=${DOWNLOADS};
        [ ! -s "${package_path}/${package_name}" ] && {
            set -f
            rm -f "${package_name}";
            set +f
            writeJSONResponseErr "result=>4078" "message=>Error loading file from URL";
            die -q;
        }
    fi
}

function _unpack(){
    APPWEBROOT=$1;
    shopt -s dotglob;
    set -f
    rm -Rf ${APPWEBROOT}/*;
    set +f
    shopt -u dotglob;

    [[ ! -d "$APPWEBROOT" ]] && { mkdir -p $APPWEBROOT;}
    if [[ ${package_url} =~ .zip$ ]] || [[ ${package_name} =~ .zip$ ]]
    then
        $UNZIP -o "${package_path}/${package_name}" -d "$APPWEBROOT" 2>>$ACTIONS_LOG 1>/dev/null;
        rcode=$?;
        [ "$rcode" -eq 1 ] && return 0 || return $rcode
    fi
    if [[ ${package_url} =~ .tar$ ]] || [[ ${package_name} =~ .tar$ ]]
    then
       $TAR --overwrite -xpf "${package_path}/${package_name}" -C "$APPWEBROOT" >> $ACTIONS_LOG 2>&1;
       return $?;
    fi
    if [[ ${package_url} =~ .tar.gz$ ]] || [[ ${package_name} =~ .tar.gz$ ]]
    then
       $TAR --overwrite -xpzf "${package_path}/${package_name}" -C "$APPWEBROOT" >> $ACTIONS_LOG 2>&1;
       return $?;
    fi
    if [[ ${package_url} =~ .tar.bz2$ ]] || [[ ${package_name} =~ .tar.bz2$ ]]
    then
       $TAR --overwrite -xpjf  "${package_path}/${package_name}" -C "$APPWEBROOT" >> $ACTIONS_LOG 2>&1;
       return $?;
    fi
}

function _shiftContentFromSubdirectory(){
    local appwebroot=$1;
    shopt -s dotglob;
    amount=`ls $appwebroot | wc -l` ;
    if  [ "$amount" -eq 1 ]
    then
        object=`ls "$appwebroot"`;
        if [ -d "${appwebroot}/${object}/${object}" ]
        then
                amount=`ls "$appwebroot/$object" | wc -l`;
                if [ "$amount" -gt 1 ]
                then
                       # in $appwebroot/$object more then one file - exit
                       shopt -u dotglob;
                       return 0;
                fi
                if [ "$amount" -eq 1 ]
                then
                       set +f
                       mv "${appwebroot}/${object}/${object}/"*  "${appwebroot}/${object}/" 2>/dev/null;
                       set -f
                       if [ "$?" -ne 0 ]
                       then
                                shopt -u dotglob;
                                return 0;
                       fi
                fi
                [ -d "${appwebroot}/${object}/${object}" ] && rm -rf "${appwebroot}/${object}/${object}" ;
                shopt -u dotglob;
                return 0;
        fi
        amount=`ls "$appwebroot/$object" | wc -l` ;
        if [ "$amount" -gt 0 ]
        then
            set +f
            mv "$appwebroot/$object/"* "$appwebroot/" 2>/dev/null ;
            set -f
            [ -d "$appwebroot/$object" ] && rm -rf "$appwebroot/$object";
        else
            rmdir "$appwebroot/$object" && [ `basename $appwebroot` != "ROOT" ] && { 
                     [ -d "$appwebroot" ] &&  rm -rf "$appwebroot";
            } ;  writeJSONResponceErr "result=>4072" "message=>Empty package!"; die -q; 
        fi
    fi
    shopt -u dotglob;   
}


function _clearCache(){
    if [[ -d "$DOWNLOADS" ]]
    then
           shopt -s dotglob;
       rm -Rf ${DOWNLOADS}/*;
       shopt -u dotglob;
    fi
}

function _updateOwnership(){
    shopt -s dotglob;
        APPWEBROOT=$1;
        chown -R "$DATA_OWNER" "$APPWEBROOT" 2>>"$JEM_CALLS_LOG";
        chmod -R a+r  "$APPWEBROOT" 2>>"$JEM_CALLS_LOG";
    chmod -R u+w  "$APPWEBROOT" 2>>"$JEM_CALLS_LOG";
    shopt -u dotglob;
}

function prepareContext(){
    local context=$1;
    if [ "$context" == "ROOT" ]
    then
            APPWEBROOT=${WEBROOT}/ROOT/;
    else
        APPWEBROOT=$WEBROOT/$context/;
    fi


}

function _deploy(){
    echo "Starting deploying application ..." >> $ACTIONS_LOG 2>&1;
    package_url=$1;
    context=$2;
    ext=$3;
    [ ! -d "$DOWNLOADS" ] && { mkdir -p "$DOWNLOADS"; }
    _clearCache;
    prepareContext ${context} ;
    getPackageName;
    if [[ -f "${APPWEBROOT%/}" ]]
    then
        rm -f "${APPWEBROOT%/}";
    fi
    _unpack $APPWEBROOT && echo "Application deployed successfully!" >> $ACTIONS_LOG 2>&1 || {  if [ "$context" != "ROOT" ];then rm -rf $APPWEBROOT 1>/dev/null 2>&1; fi;  writeJSONResponceErr "result=>4071" "message=>Cannot unpack package!"; die -q; }
    _shiftContentFromSubdirectory $APPWEBROOT;
    if [ "$context" != "ROOT" ]
    then
        _setContext $context;
    fi
    _finishDeploy;
    service cartridge restart 2>>/dev/null 1>>/dev/null;
}

function _finishDeploy(){
    _updateOwnership $APPWEBROOT;
    local requirements_file=${OPENSHIFT_PYTHON_REQUIREMENTS_PATH:-requirements.txt}
    if [ -f ${OPENSHIFT_REPO_DIR}/ROOT/${requirements_file} ]; then
        echo "Checking for pip dependency listed in ${requirements_file} file.."
        ( cd $OPENSHIFT_REPO_DIR; pip install -r ${OPENSHIFT_REPO_DIR}/ROOT/${requirements_file} $OPENSHIFT_PYTHON_MIRROR )
    fi
    if [ -f ${OPENSHIFT_REPO_DIR}/ROOT/setup.py ]; then
        echo "Running setup.py script.."
        ( cd $OPENSHIFT_REPO_DIR; python ${OPENSHIFT_REPO_DIR}/ROOT/setup.py develop $OPENSHIFT_PYTHON_MIRROR )
    fi
    pip install --upgrade pip
    _clearCache;
}

function _undeploy(){
    local context=$1;
    if [ "x$context" == "xROOT" ]
    then
        APPWEBROOT=${WEBROOT}/ROOT;
        if [[ -d "$APPWEBROOT" ]]
        then
                shopt -s dotglob;
                rm -Rf $APPWEBROOT/* ;
                shopt -u dotglob;
        fi
    else
        APPWEBROOT=$WEBROOT/$context
        if [[ -d "$APPWEBROOT" ]]
    then
       rm -Rf $APPWEBROOT ;
    fi
        _delContext $context;
    fi
}

function describeDeploy(){
    echo "deploy php application \n\t\t -u \t <package URL> \n\t\t -c \t <context> \n\t\t -e \t zip | tar | tar.gz | tar.bz";
}

function describeUndeploy(){
    echo "undeploy php application \n\t\t -c \t <context>";
}

function describeRename(){
    echo "rename php context \n\t\t -n \t <new context> \n\t\t -o \t <old context>\n\t\t -e \t <extension>";
}
