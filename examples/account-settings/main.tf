provider "aws" {
  region = var.region
}

module "account_settings" {
  #checkov:skip=CKV_AWS_356:skipping 'Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions'
  #checkov:skip=CKV_AWS_111:skipping 'Ensure IAM policies does not allow write access without constraints'
  source  = "../../modules/account-settings"
  context = module.this.context
}
