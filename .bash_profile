# Replacement for docker-machine command, that adds subcommands developed
# to enhance usability on osx/behind company proxy.
# default subcommnads fallback on the original docker-machine command. 
docker-machine-extensions () {
  case $1 in
    #TODO:document extensions
    connect)  shift; docker-machine-connect $@;;
    hostname) shift; docker-machine-hostname $@;;
    proxy)    shift; docker-machine-proxy $@;;
    registry) shift; docker-machine-registry $@;;
    *)        docker-machine $@;;
  esac
}

alias docker-machine="docker-machine-extensions"

# Set up the environment for the Docker client, connecting to 
# the given docker machine.
docker-machine-connect () { 
  #defaults 
  opt_unset=

  #options
  OPTIND=1
  while getopts  ":hu" opt
  do
    case $opt in
    u)  opt_unset=1;;
    h)  echo "Usage: docker-machine connect [OPTIONS] [arg...]" >&2; return 1;;
    \?) echo "Invalid option: -$OPTARG" >&2; return 1;;
    esac
  done
  shift $((OPTIND-1))

  # arg
  if [ $# -ne 1 ]; then
    echo "Error: Expected one machine name as argument" >&2
    return 1
  fi
  machine=$1

  #TODO: errore se docker-machine non running

  # behaviour
  if [ -z "$opt_unset" ]; then
    ## setting env var
    eval "$(docker-machine env $machine)"
  else
    ## un-setting env var

    # NB.Custom implementation instead docker-machine env -u because 
    # it seems that commands generated are wrong...
    unset DOCKER_TLS_VERIFY 
    unset DOCKER_HOST 
    unset DOCKER_CERT_PATH 
    unset DOCKER_MACHINE_NAME 
  fi
}

# Set up a hostname for accessing Docker-machine ip.
docker-machine-hostname () { 
  #defaults 
  domain="docker"
  opt_unset=

  #options
  OPTIND=1
  while getopts  ":hud:" opt
  do
    case $opt in
    u)  opt_unset=1;;
    d)  domain=$OPTARG;;
    h)  echo "Usage: docker-machine hostname [OPTIONS] [arg...]" >&2; return 1;;
    \?) echo "Invalid option: -$OPTARG" >&2; return 1;;
    :)  echo "Option -$OPTARG requires an argument." >&2; return 1;;
    esac
  done
  shift $((OPTIND-1))

  #args
  if [ $# -ne 1 ]; then 
    echo "Error: Expected to get one or more machine names as arguments" >&2
    return 1
  fi

  # behaviour
  for machine in "$@"
  do
    #TODO: errore se docker-machine non running 

    if [ -z "$opt_unset" ]; then
      ## setting hostname
      echo "Adding hostname for docker-machine $machine in /etc/hosts; sudo password might be required.."

      # if ip not actual
      if [[ $(cat /etc/hosts | grep -c -e "$(docker-machine ip $machine) $machine\.$domain") = 0 ]]; then
        #updates
        sudo sed -i "" "/ $machine.$domain/d" /etc/hosts
        sudo bash -c "echo '$(docker-machine ip $machine) $machine.$domain' >> /etc/hosts"
      fi
      echo $(cat /etc/hosts | grep -e " $machine\.$domain")
    else
      ## un-setting hostname
      echo "Removing hostname for docker-machine $machine in /etc/hosts; sudo password might be required.."

      # if hostname set 
      if [[ $(cat /etc/hosts | grep -c -e " $machine\.$domain") = 1 ]]; then
        # removing
        sudo sed -i "" "/ $machine.$domain/d" /etc/hosts
      fi      
    fi
  done
}

# Set up the proxy for the Docker machine, used for image push/pull
docker-machine-proxy () { 
  #defaults 
  opt_unset=
  opt_force=
  http=
  https=
  no_proxy=

  #options
  OPTIND=1
  while getopts  ":hfu-:" opt
  do
    case $opt in
    u)  opt_unset=1;;
    f)  opt_force=1;;
    h)  echo "Usage: docker-machine proxy [OPTIONS] [arg...]" >&2; return 1;;
    -)
        #TODO validare che value non sia un altra options (che value non sia missing)
        case ${OPTARG} in
        http=*)     http=${OPTARG#*=};;
        https=*)    https=${OPTARG#*=};;
        no_proxy=*) no_proxy=${OPTARG#*=};;
        *)
            #TODO capire
            if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                echo "Invalid option: --${OPTARG}" >&2
            fi
            ;;
        esac;;
    \?) echo "Invalid option: -$OPTARG" >&2; return 1;;
    :)  echo "Option -$OPTARG requires an argument." >&2; return 1;;
    esac
  done
  shift $((OPTIND-1))

  # arg
  if [ $# -ne 1 ]; then
    echo "Error: Expected one machine name as argument" >&2
    return 1
  fi
  machine=$1

  #TODO: errore se docker-machine non running

  #TODO: consistenza opzioni:
  #  -u + altre opzioni non accettabile
  # http, https, no_proxy, se presenti devono esserci tutti
  
  # create directory for docker-machine settings if not exists   
  directory="$HOME/.bash-extensions/docker-machine/$machine"
  if [ ! -d $directory ]; then mkdir -p $directory; fi

  # sets path for proxy settings
  file_proxy="$directory/proxy"

  # behaviour
  if [ -z "$opt_unset" ]; then
    ## set proxy
    if [ ! -z "$http" ] && [ ! -z "$https" ] && [ ! -z "$no_proxy" ]; then
      ## intialize & set proxy

      # cleanup proxy settings for docker machine
      if [ -f $file_proxy ]; then rm $file_proxy; fi

      # stores proxy settings for docker machine
      echo "HTTP_PROXY=$http"   >> $file_proxy
      echo "HTTPS_PROXY=$https" >> $file_proxy
      echo "NO_PROXY=$no_proxy" >> $file_proxy

      # set target proxy for docker machine
      http_target=$http
      https_target=$https
      no_proxy_target=$no_proxy
    else
      ## apply proxy
      
      # if proxy settings are already in place for docker machine
      if [ -f $file_proxy ]; then
        # retrives and set proxy settings for docker machine
        http_target="$(cat $file_proxy | grep -e 'HTTP_PROXY=' | cut -d = -f2)"
        https_target="$(cat $file_proxy | grep -e 'HTTPS_PROXY=' | cut -d = -f2)"
        no_proxy_target="$(cat $file_proxy | grep -e 'NO_PROXY=' | cut -d = -f2)"
      else
        echo "Error! It is necessary to initialize proxy configuration for docker-machine $machine-name. Use: docker-machine proxy --http=... --https=... --no_proxy=... $machine"
        return 1
      fi
    fi
  else
    ## un-set proxy

    # set target proxy for docker machine
    http_target=
    https_target=
    no_proxy_target=
  fi

  # get current settings
  http_current=$(docker-machine ssh $machine cat /var/lib/boot2docker/profile | grep -e 'HTTP_PROXY=' | cut -d = -f2)
  https_current=$(docker-machine ssh $machine cat /var/lib/boot2docker/profile | grep -e 'HTTPS_PROXY=' | cut -d = -f2)
  no_proxy_current=$(docker-machine ssh $machine cat /var/lib/boot2docker/profile | grep -e 'NO_PROXY=' | cut -d = -f2)

  #echo "current: $http_current $https_current $no_proxy_current"
  #echo "target : $http_target $https_target $no_proxy_target"

  # if current <> target
  if [ "$http_current" != "$http_target" ] || [ "$https_current" != "$https_target" ] || [ "$no_proxy_current" != "$no_proxy_target" ]; then 
    
    # Asks confirmation for restart
    if [ -z "$opt_force" ]; then
      read -r -p "This operation require a restart of docker-machine $machine. Continue? [y/N] " response
      if [[ ! $response =~ ^([yY][eE][sS]|[yY])$ ]]; then return 1; fi
    fi
    
    # set paht for tmp copy of profile file 
    file_profile="$directory/profile"

    # retrive current profile (original)
    docker-machine scp "$machine:/var/lib/boot2docker/profile" $file_profile > /dev/null

    # remove proxy setting (if existings)
    sed -i "" "/HTTP_PROXY=/d" $file_profile
    sed -i "" "/HTTPS_PROXY=/d" $file_profile
    sed -i "" "/NO_PROXY=/d" $file_profile  

    # set new proxy 
    if [ ! -z "$http_target" ] && [ ! -z "$https_target" ] && [ ! -z "$no_proxy_target" ]; then 
      echo "export HTTP_PROXY=$http_target" >> $file_profile
      echo "export HTTPS_PROXY=$https_target" >> $file_profile
      echo "export NO_PROXY=$no_proxy_target" >> $file_profile
    fi

    # copy update profile and remove tmp files
    docker-machine scp $file_profile "$machine:/home/docker/profile" > /dev/null
    docker-machine ssh $machine sudo cp /home/docker/profile /var/lib/boot2docker/profile 
    docker-machine ssh $machine rm /home/docker/profile
    rm $file_profile

    # restarts
    echo "Restarting docker-machine $machine..."
    docker-machine ssh $machine sudo /etc/init.d/docker restart > /dev/null
  fi
}

# Set up the Docker-machine for accessing a private registry 
docker-machine-registry () { 
  #defaults 
  opt_unset=
  opt_force=
  cert=

  #options
  OPTIND=1
  while getopts  ":hufc:" opt
  do
    case $opt in
    u)  opt_unset=1;;
    f)  opt_force=1;;
    c)  cert=$OPTARG;; #TODO gestire 1 sola machine alla volta, spostare cert dopo machine (non opzione ma arg)
    h)  echo "Usage: docker-machine registry [OPTIONS] [arg...]" >&2; return 1;;
    \?) echo "Invalid option: -$OPTARG" >&2; return 1;;
    :)  echo "Option -$OPTARG requires an argument." >&2; return 1;;
    esac
  done
  shift $((OPTIND-1))

  #args
  if [ -z "$cert" ]; then 
    echo "Error: Expected to get certificate. use docker-machine registry -c ... $machine" >&2
    return 1
  fi

  # arg
  if [ $# -ne 1 ]; then
    echo "Error: Expected one machine name as argument" >&2
    return 1
  fi
  machine=$1

  # Asks confirmation for restart
  if [ -z "$opt_force" ]; then
    read -r -p "This operation require a restart of involved docker-machines. Continue? [y/N] " response
    if [[ ! $response =~ ^([yY][eE][sS]|[yY])$ ]]; then return 1; fi
  fi

  #TODO: errore se docker-machine non running 
  certfile="$(basename $cert)"

  #remove current certificate if existing
  docker-machine ssh $machine sudo rm -f /var/lib/boot2docker/$certfile

  if [ -z "$opt_unset" ]; then
    ## add cert
    docker-machine scp $cert "$machine:/home/docker/$certfile" > /dev/null
    docker-machine ssh $machine sudo cp /home/docker/$certfile /var/lib/boot2docker/$certfile
    docker-machine ssh $machine rm /home/docker/$certfile
  fi

  ## bootstrap.sh (re-created every times)
  
  # remove current bootsync.sh if existing
  docker-machine ssh default sudo rm -f /var/lib/boot2docker/bootsync.sh

  # create directory for docker-machine settings if not exists   
  directory="$HOME/.bash-extensions/docker-machine/$machine"
  if [ ! -d $directory ]; then mkdir -p $directory; fi
  
  # create locally bootsync.sh
  rm -f $directory/bootsync.sh
  filename="$(basename $cert)"
  echo '
    #!/bin/sh
    for cert in /var/lib/boot2docker/*.crt; do
      filename=$(basename $cert)
      sudo cat /var/lib/boot2docker/$filename >> /etc/ssl/certs/ca-certificates.crt
      sudo mkdir -p /etc/docker/certs.d/${filename%.*}/
      sudo cat /var/lib/boot2docker/$filename >> /etc/docker/certs.d/${filename%.*}/ca.crt
    done  
  ' > $directory/bootsync.sh

  # copy to docker-machine
  docker-machine scp $directory/bootsync.sh "$machine:/home/docker/bootsync.sh" > /dev/null
  docker-machine ssh $machine sudo cp /home/docker/bootsync.sh /var/lib/boot2docker/bootsync.sh
  docker-machine ssh $machine sudo chmod 755 /var/lib/boot2docker/bootsync.sh

  rm -f $directory/bootsync.sh

  # restarts
  echo "Restarting docker-machine $machine..."
  docker-machine restart $machine 
}
