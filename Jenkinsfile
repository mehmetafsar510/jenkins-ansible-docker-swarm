pipeline {
    agent { label "master" }
    environment {
        PATH=sh(script:"echo $PATH:/usr/local/bin", returnStdout:true).trim()
        APP_NAME="phonebook"
        APP_STACK_NAME="$APP_NAME-App-QA-${BUILD_NUMBER}"
        AWS_REGION="us-east-1"
        CFN_KEYPAIR="the-doctor"
        CFN_TEMPLATE="docker-swarm-infrastructure-cfn-template.yml"
        ANSIBLE_PRIVATE_KEY_FILE="${WORKSPACE}/.ssh/${CFN_KEYPAIR}"
        ANSIBLE_HOST_KEY_CHECKING="False"
        APP_REPO_NAME="clarusway-repo/phonebook-app-qa" 
        AWS_REGION="us-east-1" 
        ECR_REGISTRY="717860527362.dkr.ecr.us-east-1.amazonaws.com" 
    }
    stages {
        stage('get-keypair'){
            agent any
            steps{
                sh '''
                    if [ -f "${CFN_KEYPAIR}" ]
                    then 
                        echo "file exists..."
                    else
                        aws ec2 create-key-pair \
                          --region ${AWS_REGION} \
                          --key-name ${CFN_KEYPAIR} \
                          --query KeyMaterial \
                          --output text > ${CFN_KEYPAIR}

                        chmod 400 ${CFN_KEYPAIR}
                        
                        ssh-keygen -y -f ${CFN_KEYPAIR} >> ${CFN_KEYPAIR}.pub
                        sudo mkdir -p ${WORKSPACE}/.ssh
                        sudo mv -f ${CFN_KEYPAIR} ${WORKSPACE}/.ssh
                    fi
                '''                
            }
        }
        stage('creating ECR Repository'){
            agent any
            steps{
                echo 'creating ECR Repository'
                sh '''
                    RepoArn=$(aws ecr describe-repositories | grep ${APP_REPO} |cut -d '"' -f 4| head -n 1 )  || true
                    if [ "$RepoArn" == '' ]
                    then
                        aws ecr create-repository \
                          --repository-name ${APP_REPO} \
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
                            sh "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${WORKSPACE}/.ssh/${CFN_KEYPAIR} ec2-user@${GRAND_MASTER_PUBLIC_IP} hostname"
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
        failure {
            echo 'Tear down the Docker Swarm infrastructure using AWS CLI'
            sh "aws cloudformation delete-stack --region ${AWS_REGION} --stack-name ${APP_STACK_NAME}"
        }
    }
}