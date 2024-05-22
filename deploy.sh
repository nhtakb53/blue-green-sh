#!/bin/bash

# 전역 색상 설정
COLOR_BLUE="\033[94m"
COLOR_GREEN="\033[32m"
COLOR_RESET="\033[0m"

export JAVA_HOME=/home/actdev/jdk-21
export APP_HOME=.
export JAVA_OPTS=""
export APP_NAME="content-admin-0.0.1-SNAPSHOT.jar"
export PROFILE="-Dspring.profiles.active=dev"

export PORT_BLUE_MAIN="18080"
export PORT_BLUE_MANAGEMENT="8081"
export PORT_GREEN_MAIN="18081"
export PORT_GREEN_MANAGEMENT="8082"

function switch_nginx_config {
    CURRENT_CONFIGURATION=$1
    if [ "$CURRENT_CONFIGURATION" == "blue" ]; then
        cp /etc/nginx/conf.d/ccube.conf.green /etc/nginx/conf.d/ccube.conf
        echo -e "${COLOR_GREEN}Switched to green configuration.${COLOR_RESET}"
    else
        cp /etc/nginx/conf.d/ccube.conf.blue /etc/nginx/conf.d/ccube.conf
        echo -e "${COLOR_BLUE}Switched to blue configuration.${COLOR_RESET}"
    fi

    # Reload NGINX to apply changes
    sudo nginx -s reload
    echo "NGINX reloaded."
}

# Determines which version is currently running based on management port
function check_running_version {
    if curl -f http://localhost:$PORT_BLUE_MANAGEMENT/actuator/health >/dev/null 2>&1; then
        echo "blue"
    elif curl -f http://localhost:$PORT_GREEN_MANAGEMENT/actuator/health >/dev/null 2>&1; then
        echo "green"
    else
        echo "none"
    fi
}

function stop_application {
    PORT_MANAGEMENT=$1
    echo "Attempting to stop application using management port $PORT_MANAGEMENT..."

    # lsof를 사용하여 포트를 사용하는 프로세스 ID(PID)를 찾습니다.
    PID=$(lsof -ti:$PORT_MANAGEMENT)

    if [ ! -z "$PID" ]; then
        echo "Found old process $PID on port $PORT_MANAGEMENT, attempting to stop..."
        # 해당 PID의 프로세스를 종료합니다.
        kill -TERM $PID && echo "Successfully stopped the old process." || echo "Failed to stop the old process."

        # 프로세스가 종료되었는지 확인하고, 필요한 경우 강제 종료합니다.
        sleep 5
        if kill -0 $PID 2>/dev/null; then
            echo "Process did not terminate gracefully, forcing..."
            kill -KILL $PID
        fi
    else
        echo "No process found using port $PORT_MANAGEMENT."
    fi
}

# Starts the application with the specified profile and ports, then checks health
function start_and_check_health {
    JAR_FILE=$APP_HOME/$APP_NAME
    PROFILE=$2
    PORT_MAIN=$3
    PORT_MANAGEMENT=$4

    echo "Starting $APP_NAME on ports $PORT_MAIN and $PORT_MANAGEMENT..."
    nohup $JAVA_HOME/bin/java $JAVA_OPTS $PROFILE -Dserver.port=$PORT_MAIN -Dmanagement.server.port=$PORT_MANAGEMENT -jar $JAR_FILE &>/dev/null &
    sleep 10 # Allow some time for the application to start

    # Check application health
    attempts=0
    while ! curl -f http://localhost:$PORT_MANAGEMENT/actuator/health >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        echo "Checking status... ($attempts/10)"
        if [ $attempts -gt 5 ]; then
            echo "Health check failed for $APP_NAME on port $PORT_MANAGEMENT."
            exit 1
        fi
        sleep 5
    done
    echo "$APP_NAME is healthy on port $PORT_MANAGEMENT."
}

function deploy {
    CURRENT_VERSION=$(check_running_version)
    if [ "$CURRENT_VERSION" == "blue" ]; then
        DEPLOY_PORT_MAIN=$PORT_GREEN_MAIN
        DEPLOY_PORT_MANAGEMENT=$PORT_GREEN_MANAGEMENT
        OLD_PORT_MANAGEMENT=$PORT_BLUE_MANAGEMENT
        NEW_APP_NAME="green-${APP_NAME}"
        echo -e "${COLOR_GREEN}Deploying $APP_NAME on green.${COLOR_RESET}"
    else
        DEPLOY_PORT_MAIN=$PORT_BLUE_MAIN
        DEPLOY_PORT_MANAGEMENT=$PORT_BLUE_MANAGEMENT
        OLD_PORT_MANAGEMENT=$PORT_GREEN_MANAGEMENT
        NEW_APP_NAME="blue-${APP_NAME}"
        echo -e "${COLOR_BLUE}Deploying $APP_NAME on blue.${COLOR_RESET}"
    fi

    # 애플리케이션 파일 복사 및 이름 변경
    cp /home/actdev/cms-core/$APP_NAME /home/actdev/cms-core/$NEW_APP_NAME
    if [ $? -ne 0 ]; then
        echo -e "Failed to copy $APP_NAME to $NEW_APP_NAME."
        exit 1
    fi

    APP_NAME=$NEW_APP_NAME

    start_and_check_health $APP_NAME $PROFILE $DEPLOY_PORT_MAIN $DEPLOY_PORT_MANAGEMENT
    switch_nginx_config $CURRENT_VERSION

    if [ "$CURRENT_VERSION" != "none" ]; then
        stop_application $OLD_PORT_MANAGEMENT
    fi

    echo "Deployment successful. $APP_NAME is now running on port $DEPLOY_PORT_MAIN."
}

deploy
