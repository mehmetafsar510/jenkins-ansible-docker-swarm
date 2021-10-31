pipeline {
    agent any
    environment {
        PATH=sh(script:"echo $PATH:/usr/local/bin", returnStdout:true).trim()
        MYSQL_DATABASE_PASSWORD = "Clarusway"
        MYSQL_DATABASE_USER = "admin"
        MYSQL_DATABASE_DB = "phonebook"
        MYSQL_DATABASE_PORT = 3306
        APP_NAME="phonebook"
        APP_STACK_NAME="$APP_NAME-App-QA-${BUILD_NUMBER}"
        CFN_KEYPAIR="the-doctor"
        CFN_TEMPLATE="docker-swarm-infrastructure-cfn-template.yml"
        ANSIBLE_PRIVATE_KEY_FILE="${JENKINS_HOME}/.ssh/${CFN_KEYPAIR}.pem"
        ANSIBLE_HOST_KEY_CHECKING="False"
        APP_REPO_NAME="clarusway-repo/phonebook-app-qa" 
        AWS_REGION="us-east-1" 
        ECR_REGISTRY="717860527362.dkr.ecr.us-east-1.amazonaws.com" 
    }
    stages {
        stage("compile"){
           agent{
               docker{
                   image 'python:alpine'
               }
           }
           steps{
               withEnv(["HOME=${env.WORKSPACE}"]) {
                    sh 'pip install -r requirements.txt'
                    sh 'python -m py_compile src/*.py'
                    stash(name: 'compilation_result', includes: 'src/*.py*')
                }
           }
        }

        stage('creating RDS for test stage'){
            agent any
            steps{
                echo 'creating RDS for test stage'
                sh '''
                    RDS=$(aws rds describe-db-instances --region ${AWS_REGION}  | grep mysql-instance |cut -d '"' -f 4| head -n 1)  || true
                    if [ "$RDS" == '' ]
                    then
                        aws rds create-db-instance \
                          --region ${AWS_REGION} \
                          --db-instance-identifier mysql-instance \
                          --db-instance-class db.t2.micro \
                          --engine mysql \
                          --db-name ${MYSQL_DATABASE_DB} \
                          --master-username ${MYSQL_DATABASE_USER} \
                          --master-user-password ${MYSQL_DATABASE_PASSWORD} \
                          --allocated-storage 20 \
                          --tags 'Key=Name,Value=masterdb'
                          
                    fi
                '''
            script {
                while(true) {
                        
                        echo "RDS is not UP and running yet. Will try to reach again after 10 seconds..."
                        sleep(10)

                        endpoint = sh(script:'aws rds describe-db-instances --region ${AWS_REGION} --db-instance-identifier mysql-instance --query DBInstances[*].Endpoint.Address --output text | sed "s/\\s*None\\s*//g"', returnStdout:true).trim()

                        if (endpoint.length() >= 7) {
                            echo "My Database Endpoint Address Found: $endpoint"
                            env.MYSQL_DATABASE_HOST = "$endpoint"
                            break
                        }
                    }
                }
            }
        }

        stage('create phonebook table in rds'){
            agent any
            steps{
                sh "mysql -u ${MYSQL_DATABASE_USER} -h ${MYSQL_DATABASE_HOST} -p${MYSQL_DATABASE_PASSWORD} < phonebook.sql"
            }
        } 
       
        stage('test'){
            agent {
                docker {
                    image 'python:alpine'
                }
            }
            steps {
                withEnv(["HOME=${env.WORKSPACE}"]) {
                    sh 'python -m pytest -v --junit-xml results.xml src/appTest.py'
                }
            }
            post {
                always {
                    junit 'results.xml'
                }
            }
        }  

        stage('creating .env for docker-compose'){
            agent any
            steps{
                script {
                    echo 'creating .env for docker-compose'
                    sh "cd ${WORKSPACE}"
                    writeFile file: '.env', text: "ECR_REGISTRY=${ECR_REGISTRY}\nAPP_REPO_NAME=${APP_REPO_NAME}:latest"
                }
            }
        }
        stage('get-keypair'){
            agent any
            steps{
                sh '''
                    if [ -f "${CFN_KEYPAIR}.pem" ]
                    then 
                        echo "file exists..."
                    else
                        aws ec2 create-key-pair \
                          --region ${AWS_REGION} \
                          --key-name ${CFN_KEYPAIR} \
                          --query KeyMaterial \
                          --output text > ${CFN_KEYPAIR}.pem

                        chmod 400 ${CFN_KEYPAIR}.pem
                        
                        ssh-keygen -y -f ${CFN_KEYPAIR}.pem >> ${CFN_KEYPAIR}.pub
                        cp -f ${CFN_KEYPAIR}.pem ${JENKINS_HOME}/.ssh
                        chown jenkins:jenkins ${JENKINS_HOME}/.ssh/${CFN_KEYPAIR}.pem

                    fi
                '''                
            }
        }
        stage('creating ECR Repository'){
            agent any
            steps{
                echo 'creating ECR Repository'
                sh '''
                    RepoArn=$(aws ecr describe-repositories --region ${AWS_REGION} | grep ${APP_REPO} |cut -d '"' -f 4| head -n 1 )  || true
                    if [ "$RepoArn" == '' ]
                    then
                        aws ecr create-repository \
                          --repository-name ${APP_REPO_NAME} \
                          --image-scanning-configuration scanOnPush=false \
                          --image-tag-mutability MUTABLE \
                          --region ${AWS_REGION}
                        
                    fi
                '''
            }
        }
        stage('building Docker Image') {
            steps {
                echo 'building Docker Image'
                sh 'docker build --force-rm -t "$ECR_REGISTRY/$APP_REPO_NAME:latest" .'
                sh 'docker image ls'
            }
        }
        stage('pushing Docker image to ECR Repository'){   
            steps {
                echo 'pushing Docker image to ECR Repository'
                sh 'aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin "$ECR_REGISTRY"'
                sh 'docker push "$ECR_REGISTRY/$APP_REPO_NAME:latest"'

            }
        }
        stage('Create QA Environment Infrastructure') {
            steps {
                echo 'Creating Infrastructure for QA Environment with Cloudfomation'
                sh "aws cloudformation create-stack --region ${AWS_REGION} --stack-name ${APP_STACK_NAME} --capabilities CAPABILITY_IAM --template-body file://${CFN_TEMPLATE} --parameters ParameterKey=KeyPairName,ParameterValue=${CFN_KEYPAIR}"

                script {
                    while(true) {
                        echo "Docker Grand Master is not UP and running yet. Will try to reach again after 10 seconds..."
                        sleep(10)

                        ip = sh(script:"aws ec2 describe-instances --region ${AWS_REGION} --filters Name=tag-value,Values=grand-master Name=tag-value,Values=${APP_STACK_NAME} --query Reservations[*].Instances[*].[PublicIpAddress] --output text", returnStdout:true).trim()

                        if (ip.length() >= 7) {
                            echo "Docker Grand Master Public Ip Address Found: $ip"
                            env.GRAND_MASTER_PUBLIC_IP = "$ip"
                            break
                        }
                    }
                    while(true) {
                        try{
                            sh "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${JENKINS_HOME}/.ssh/${CFN_KEYPAIR}.pem ec2-user@${GRAND_MASTER_PUBLIC_IP} hostname"
                            echo "Docker Grand Master is reachable with SSH."
                            break
                        }
                        catch(Exception){
                            echo "Could not connect to Docker Grand Master with SSH, I will try again in 10 seconds"
                            sleep(10)
                        }
                    }
                }
            }
        }

        stage('Create Docker Swarm for QA Environment') {
            steps {
                echo "Setup Docker Swarm for QA Environment for ${APP_NAME} App"
                echo "Update dynamic environment"
                sh "sed -i 's/APP_STACK_NAME/${APP_STACK_NAME}/' dynamic_inventory_aws_ec2.yaml"
                echo "Swarm Setup for all nodes (instances)"
                sh "ansible-playbook  -b ./ansible/pb_setup_for_all_docker_swarm_instances.yaml"
                echo "Swarm Setup for Grand Master node"
                sh "ansible-playbook  -b ./ansible/pb_initialize_docker_swarm.yaml"
                echo "Swarm Setup for Other Managers nodes"
                sh "ansible-playbook  -b ./ansible/pb_join_docker_swarm_managers.yaml"
                echo "Swarm Setup for Workers nodes"
                sh "ansible-playbook -b ./ansible/pb_join_docker_swarm_workers.yaml"
                sh 'ansible-playbook -b --extra-vars "workspace=${WORKSPACE} app_name=${APP_NAME} aws_region=${AWS_REGION} ecr_registry=${ECR_REGISTRY}" ./ansible/pb_deploy_app_on_docker_swarm.yaml'
            }
        }
    }
    post {
        success {
            echo "You are Greattt...You can visit https://$FQDN"
        }
    }
}