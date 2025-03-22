pipeline {
    agent any

    stages {
        stage('Clone') {
            steps {
                git url: 'https://github.com/jasontsaicc/Jason_jenkins_test.git', branch: 'main'
            }
        }

        stage('Build') {
            steps {
                echo '🔧 Building project...'
            }
        }

        stage('Test') {
            steps {
                echo '✅ Running tests...'
            }
        }

        stage('Deploy') {
            steps {
                echo '🚀 Deploying...'
            }
        }
    }
}