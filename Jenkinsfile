pipeline {
    agent any

    environment {
        AWS_REGION = 'ap-northeast-1'
        ECR_REPO =  'jenkins-test-app'
        IMAGE_TAG = 'latest'
        REPO_URI = "096011725235.dkr.ecr.ap-northeast-1.amazonaws.com/jenkins-test-app
        }

    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out code...'
                checkout scm
            }
        }
        stage('Build Docker Image'){
            steps{
                sh 'docker build -t ${ECR_REPO}:${IMAGE_TAG} .'
            }
        }
        stage('Login to ECR') {
            steps {
                sh '''
                    aws ecr get-login-password --region $AWS_REGION | \
                    docker login --username AWS --password-stdin $REPO_URI
                '''
            }
        }
        stage('Push Docker Image') {
            steps {
                sh '''
                    docker tag ${ECR_REPO}:${IMAGE_TAG} $REPO_URI:$IMAGE_TAG
                    docker push $REPO_URI::$IMAGE_TAG
                '''
            }
        }
    }

}