pipeline {
    agent any
    environment {
        PATH=sh(script:"echo $PATH:/usr/local/bin", returnStdout:true).trim()
        MYSQL_DATABASE_PASSWORD = "Clarusway"
        MYSQL_DATABASE_USER = "admin"
        MYSQL_DATABASE_DB = "phonebook"
        MYSQL_DATABASE_PORT = 3306
        APP_NAME="phonebook"
        APP_STACK_NAME="$APP_NAME-App-QA"
        CFN_KEYPAIR="the-doctor"
        CFN_TEMPLATE="docker-swarm-infrastructure-cfn-template.yml"
        DOMAIN_NAME = "mehmetafsar.net"
        FQDN = "clarus.mehmetafsar.net"
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
                    RepoArn=$(aws ecr describe-repositories --region ${AWS_REGION} | grep ${APP_REPO_NAME} |cut -d '"' -f 4| head -n 1 )  || true
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
                sh '''
                    MasterIp=$(aws ec2 describe-instances --region ${AWS_REGION} --filters Name=tag-value,Values=grand-master Name=tag-value,Values=${APP_STACK_NAME} --query Reservations[*].Instances[*].[PublicIpAddress] --output text)  || true
                    if [ "$MasterIp" == '' ]
                    then
                        aws cloudformation create-stack --stack-name ${APP_STACK_NAME} \
                          --capabilities CAPABILITY_IAM \
                          --template-body file://${CFN_TEMPLATE} \
                          --region ${AWS_REGION} --parameters ParameterKey=KeyPairName,ParameterValue=${CFN_KEYPAIR} 
                          
                        
                    fi
                '''
                script {
                    while(true) {
                        echo "Docker Grand Master is not UP and running yet. Will try to reach again after 10 seconds..."
                        sleep(10)

                        ip = sh(script:"aws ec2 describe-instances --region ${AWS_REGION} --filters Name=tag-value,Values=grand-master Name=tag-value,Values=${APP_STACK_NAME} --query Reservations[*].Instances[*].[PublicIpAddress] --output text | tail -n 1", returnStdout:true).trim()

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
                            sleep(10)
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

        stage('dns-record-control'){
            agent any
            steps{
                withAWS(credentials: 'mycredentials', region: 'us-east-1') {
                    script {
                        env.ZONE_ID = sh(script:"aws route53 list-hosted-zones-by-name --dns-name $DOMAIN_NAME --query HostedZones[].Id --output text | cut -d/ -f3", returnStdout:true).trim()
                        env.ELB_DNS = sh(script:"aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID --query \"ResourceRecordSets[?Name == '\$FQDN.']\" --output text | tail -n 1 | cut -f2", returnStdout:true).trim() 
                    }
                    sh "sed -i 's|{{DNS}}|$ELB_DNS|g' deleterecord.json"
                    sh "sed -i 's|{{FQDN}}|$FQDN|g' deleterecord.json"
                    sh '''
                        RecordSet=$(aws route53 list-resource-record-sets   --hosted-zone-id $ZONE_ID   --query ResourceRecordSets[] | grep -i $FQDN) || true
                        if [ "$RecordSet" != '' ]
                        then
                            aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file://deleterecord.json
                        
                        fi
                    '''
                    
                }                  
            }
        }

        stage('dns-record'){
            agent any
            steps{
                withAWS(credentials: 'mycredentials', region: 'us-east-1') {
                    script {
                        env.ELB_DNS = sh(script:'aws ec2 describe-instances --region ${AWS_REGION} --filters Name=tag-value,Values=grand-master Name=tag-value,Values=${APP_STACK_NAME} --query Reservations[*].Instances[*].[PublicIpAddress] --output text | sed "s/\\s*None\\s*//g"', returnStdout:true).trim()
                        env.ZONE_ID = sh(script:"aws route53 list-hosted-zones-by-name --dns-name $DOMAIN_NAME --query HostedZones[].Id --output text | cut -d/ -f3", returnStdout:true).trim()   
                    }
                    sh "sed -i 's|{{DNS}}|$ELB_DNS|g' dnsrecord.json"
                    sh "sed -i 's|{{FQDN}}|$FQDN|g' dnsrecord.json"
                    sh "aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file://dnsrecord.json"
                    
                }                  
            }
        }

        stage('Create Docker Swarm for QA Environment') {
            steps {
                echo "Setup Docker Swarm for QA Environment for ${APP_NAME} App" 
                echo "Update dynamic environment"
                sh "sed -i 's/{SERVERIP}/${GRAND_MASTER_PUBLIC_IP}/g' deploy.sh"
                sh "sed -i 's/{FullDomainName}/${FQDN}/g' deploy.sh"
                sh "sed -i 's/APP_STACK_NAME/${APP_STACK_NAME}/' dynamic_inventory_aws_ec2.yaml"
                sh "sed -i 's/{{key_pair}}/${CFN_KEYPAIR}.pem/' ansible.cfg"
                sh '''
                    VizArn=$(curl -s --connect-timeout 5 ${GRAND_MASTER_PUBLIC_IP}:8088 )  || true
                    if [ "$VizArn" == '' ]
                    then
                        ansible-playbook  -b ./ansible/pb_setup_for_all_docker_swarm_instances.yaml
                        ansible-playbook  -b ./ansible/pb_initialize_docker_swarm.yaml
                        ansible-playbook  -b ./ansible/pb_join_docker_swarm_managers.yaml
                        ansible-playbook -b ./ansible/pb_join_docker_swarm_workers.yaml     
                    fi
                '''
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