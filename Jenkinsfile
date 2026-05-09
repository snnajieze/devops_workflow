pipeline {
    agent any

    environment {
        AWS_REGION        = "us-east-1"
        AWS_ACCOUNT_ID    = credentials('aws-account-id')
        ECR_REPO_NAME     = "solomon-app"
        EKS_CLUSTER_NAME  = "DEMO_CLUSTER"
        K8S_NAMESPACE     = "solomon-ns"
        IMAGE_TAG         = "${BUILD_NUMBER}"
        ECR_REGISTRY      = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_FULL_NAME   = "${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {

        // ─────────────────────────────────────────
        // STAGE 1: Checkout
        // ─────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo "Checking out source code..."
                checkout scm
            }
        }

        // ─────────────────────────────────────────
        // STAGE 2: Build Docker Image
        // ─────────────────────────────────────────
        stage('Build') {
            steps {
                echo "Building Docker image: ${IMAGE_FULL_NAME}"
                // Build context is repo root so Dockerfile can access app/index.html
                sh """
                    docker build \
                        -f docker/Dockerfile \
                        -t ${IMAGE_FULL_NAME} \
                        -t ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest \
                        .
                """
            }
        }

        // ─────────────────────────────────────────
        // STAGE 3: Test
        // ─────────────────────────────────────────
        stage('Test') {
            steps {
                echo "Running container smoke test..."
                sh """
                    # Kill any leftover test container from a previous failed build
                    docker rm -f test-container 2>/dev/null || true

                    # Start the container in detached mode
                    docker run -d --name test-container -p 8081:80 ${IMAGE_FULL_NAME}

                    # Wait for Nginx to be ready
                    sleep 5

                    # Check the app returns HTTP 200
                    HTTP_STATUS=\$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081)

                    # Verify expected content is present
                    CONTENT=\$(curl -s http://localhost:8081)

                    # Cleanup container before asserting
                    docker stop test-container
                    docker rm test-container

                    # Assert HTTP 200
                    if [ "\$HTTP_STATUS" != "200" ]; then
                        echo "FAILED: Expected HTTP 200 but got \$HTTP_STATUS"
                        exit 1
                    fi

                    # Assert content contains expected text
                    if ! echo "\$CONTENT" | grep -q "Solomon Nnajieze"; then
                        echo "FAILED: Expected content not found in response"
                        exit 1
                    fi

                    echo "TEST PASSED: App returned HTTP 200 with expected content"
                """
            }
        }

        // ─────────────────────────────────────────
        // STAGE 4: Push to ECR
        // ─────────────────────────────────────────
        stage('Push to ECR') {
            steps {
                echo "Authenticating with ECR and pushing image..."
                sh """
                    # Authenticate Docker to ECR using IAM role (no stored credentials needed)
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_REGISTRY}

                    # Push versioned tag
                    docker push ${IMAGE_FULL_NAME}

                    # Push latest tag
                    docker push ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest
                """
            }
        }

        // ─────────────────────────────────────────
        // STAGE 5: Deploy to EKS
        // ─────────────────────────────────────────
        stage('Deploy to EKS') {
            steps {
                echo "Deploying to EKS cluster: ${EKS_CLUSTER_NAME}"
                sh """
                    # Update kubeconfig to point kubectl at our EKS cluster
                    aws eks update-kubeconfig \
                        --region ${AWS_REGION} \
                        --name ${EKS_CLUSTER_NAME}

                    # Apply namespace (idempotent - safe to run every time)
                    kubectl apply -f k8s/namespace.yaml --validate=false

                    # Generate deployment manifest with real image URL substituted in
                    # Using envsubst avoids modifying the tracked deployment.yaml file
                    export DEPLOY_IMAGE="${IMAGE_FULL_NAME}"
                    cat k8s/deployment.yaml | \
                        sed "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/solomon-app:IMAGE_TAG|\$DEPLOY_IMAGE|g" | \
                        kubectl apply -f - --validate=false

                    kubectl apply -f k8s/service.yaml --validate=false

                    # Wait for rollout to complete (fails pipeline if pods don't come up)
                    kubectl rollout status deployment/solomon-app \
                        -n ${K8S_NAMESPACE} \
                        --timeout=120s

                    # Print the LoadBalancer URL
                    echo "--------------------------------------"
                    echo "App is live at:"
                    kubectl get svc solomon-app-svc -n ${K8S_NAMESPACE} \
                        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
                    echo ""
                    echo "--------------------------------------"
                """
            }
        }
    }

    // ─────────────────────────────────────────
    // Post Actions
    // ─────────────────────────────────────────
    post {
        always {
            echo "Cleaning up local Docker images to free disk space..."
            sh """
                docker rmi ${IMAGE_FULL_NAME} || true
                docker rmi ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest || true
            """
        }
        success {
            echo "Pipeline completed successfully. Build #${BUILD_NUMBER} deployed."
        }
        failure {
            echo "Pipeline FAILED. Check the stage logs above for details."
        }
    }
}
