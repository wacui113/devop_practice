terraform {
  backend "s3" {
    bucket         = "hungho-bucket" 
    key            = "global/s3/terraform.tfstate"      
    region         = "us-east-2"                  
    dynamodb_table = "us-east-2"        
    encrypt        = true
  }
}
