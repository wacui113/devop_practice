

AWS_REGION="your-aws-region" 
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROJECT_NAME="coffeeshop" 





IMAGES=(
    "cuongopswat/go-coffeeshop-web:latest go-coffeeshop-web"
    "cuongopswat/go-coffeeshop-proxy:latest go-coffeeshop-proxy"
    "cuongopswat/go-coffeeshop-barista:latest go-coffeeshop-barista"
    "cuongopswat/go-coffeeshop-kitchen:latest go-coffeeshop-kitchen"
    "cuongopswat/go-coffeeshop-counter:latest go-coffeeshop-counter"
    "cuongopswat/go-coffeeshop-product:latest go-coffeeshop-product"
)


aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

if [ $? -ne 0 ]; then
    echo "ECR login failed."
    exit 1
fi

for image_pair in "${IMAGES[@]}"; do
    IFS=' ' read -r DOCKERHUB_IMAGE ECR_REPO_SUFFIX <<< "$image_pair"
    ECR_REPO_NAME="${PROJECT_NAME}-${ECR_REPO_SUFFIX}"
    ECR_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest"

    echo "Processing $DOCKERHUB_IMAGE -> $ECR_IMAGE_URI"

    
    echo "Pulling $DOCKERHUB_IMAGE..."
    docker pull $DOCKERHUB_IMAGE
    if [ $? -ne 0 ]; then
        echo "Failed to pull $DOCKERHUB_IMAGE."
        continue
    fi

    
    echo "Tagging $DOCKERHUB_IMAGE as $ECR_IMAGE_URI..."
    docker tag $DOCKERHUB_IMAGE $ECR_IMAGE_URI
    if [ $? -ne 0 ]; then
        echo "Failed to tag $DOCKERHUB_IMAGE."
        continue
    fi

    
    echo "Pushing $ECR_IMAGE_URI..."
    docker push $ECR_IMAGE_URI
    if [ $? -ne 0 ]; then
        echo "Failed to push $ECR_IMAGE_URI."
        continue
    fi

    echo "Successfully processed $DOCKERHUB_IMAGE."
    echo "------------------------------------------"
done

echo "All images processed."
