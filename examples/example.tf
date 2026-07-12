terraform {
  required_version = ">= 1.9.0"
}

module "MODULE_NAME" {
  source  = "github.com/bingamon-lab-tf-modules/MODULE_NAME/MODULE_SYSTEM"
  version = "1.0.0"

  # TFVars go here

}
