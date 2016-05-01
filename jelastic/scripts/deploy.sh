#!/bin/bash

# Simple deploy and undeploy scenarios for Jelastic Python

inherit default exceptor;
$PROGRAM unzip;

[[ -n "${WEBROOT}" ]] && [ ! -d "$WEBROOT" ] && mkdir -p ${WEBROOT};

[ -e "${MANAGE_CORE_PATH}/${COMPUTE_TYPE}"-deploy.lib ] && { include ${COMPUTE_TYPE}-deploy; }

function _setContext(){
        echo "You application just been deployed to wsgi context"
}

function _unpack(){
    package_name=`ls $DOWNLOADS`;
    APPWEBROOT=$1;
    [ ! -s "$DOWNLOADS/$package_name" ] && { 
        _clearCache;
        [ `basename ${APPWEBROOT}` != "ROOT" ] && { rmdir ${APPWEBROOT}; }
        writeJSONResponceErr "result=>4078" "message=>Error loading file from URL";
        die -q;
    }

    shopt -s dotglob; 
    rm -Rf ${APPWEBROOT}*;
    shopt -u dotglob; 
    
    ensureFileCanBeUncompressed "$DOWNLOADS/${package_name}";
    [[ ! -d "$APPWEBROOT" ]] && { mkdir -p $APPWEBROOT;}
    if [[ ${package_url} =~ .zip$ ]] || [[ ${package_name} =~ .zip$ ]]
    then
        $UNZIP -o "$DOWNLOADS/$package_name" -d "$APPWEBROOT" 2>>$ACTIONS_LOG 1>/dev/null;
    	return $?;
    fi
    if [[ ${package_url} =~ .tar$ ]] || [[ ${package_name} =~ .tar$ ]]
    then
	   $TAR --overwrite -xpf "$DOWNLOADS/$package_name" -C "$APPWEBROOT" >> $ACTIONS_LOG 2>&1;
	   return $?;
    fi
    if [[ ${package_url} =~ .tar.gz$ ]] || [[ ${package_name} =~ .tar.gz$ ]]
    then
	   $TAR --overwrite -xpzf "$DOWNLOADS/$package_name" -C "$APPWEBROOT" >> $ACTIONS_LOG 2>&1;
	   return $?;
    fi
    if [[ ${package_url} =~ .tar.bz2$ ]] || [[ ${package_name} =~ .tar.bz2$ ]]
    then
	   $TAR --overwrite -xpjf  "$DOWNLOADS/$package_name" -C "$APPWEBROOT" >> $ACTIONS_LOG 2>&1;
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
                       mv "${appwebroot}/${object}/${object}/"*  "${appwebroot}/${object}/" 2>/dev/null;
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
            mv "$appwebroot/$object/"* "$appwebroot/" 2>/dev/null ;
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
        $CHOWN -R "$DATA_OWNER" "$APPWEBROOT" 2>>"$JEM_CALLS_LOG";
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
    local package_url=$1;
    local context=$2;
    local ext=$3;
    [ ! -d "$DOWNLOADS" ] && { mkdir -p "$DOWNLOADS"; }
    _clearCache;
    ensureFileCanBeDownloaded $package_url;
    prepareContext ${context} ;
    $WGET -nv --tries=2 --content-disposition --no-check-certificate --directory-prefix=$DOWNLOADS $package_url >> $ACTIONS_LOG 2>&1;
    [ $? -gt 0 ] && { writeJSONResponceErr "result=>4078" "message=>Error loading file from URL" ; die -q; };
    # check exactly FILE - it should not exists, otherwise 'mkdir' return error
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
}

function _finishDeploy(){
    _updateOwnership $APPWEBROOT;
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

function _renameContext(){
    local newContext=$1;
    local oldContext=$2;
    if [ ! -d "$WEBROOT/$newContext" ]
    then
        mkdir -p "$WEBROOT/$newContext";
    else
        shopt -s dotglob
        rm -Rf "$WEBROOT/$newContext/"*;
        shopt -u dotglob
    fi

    if [ -d "$WEBROOT/$oldContext" ]
    then
        shopt -s dotglob;
        mv "$WEBROOT/$oldContext/"* "$WEBROOT/$newContext/" 2>/dev/null && [ "$oldContext" != "ROOT" ] && rm -rf $WEBROOT/$oldContext;
        shopt -u dotglob;
    else
        #~ echo "Can't find \"$oldContext\"" >&2;
        writeJSONResponceErr "result=>4052" "message=>Context does not exist";
        die -q;
    fi

    if [ "$newContext" == "ROOT" ]
    then
        rm -Rf $WEBROOT/$oldContext/ 2>/dev/null;
        _delContext $oldContext;
        return 0;
    else
        if [ "$oldContext" == "ROOT" ]
        then
    	    _setContext $newContext;
	else
	    rm -Rf $WEBROOT/$oldContext/ 2>/dev/null;
    	    _rename $newContext $oldContext ;
    	fi
    fi

    _updateOwnership "$WEBROOT/$newContext"

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
