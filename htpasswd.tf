resource "random_password" "password" {
  length  = 21
  special = false
}

resource "random_pet" "username" {}

module "pypiserver_secret" {
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "1.3.0"
  environment        = var.environment
  secret_name_prefix = "PYPISERVER_SECRET"
  secret_description = "Username and password for the basic http authentication on the PyPI server."
  secret_value = jsonencode(
    {
      username : random_pet.username.id
      password : random_password.password.result
      bcrypt_hash : random_password.password.bcrypt_hash
    }
  )
  readers = var.secret_readers
}

# Additional users get their own password and their own secret, so each one can be
# rotated or revoked (by removing it from var.additional_users) without touching the
# primary credential or the other users.
resource "random_password" "additional" {
  for_each = var.additional_users
  length   = 21
  special  = false
}

module "additional_user_secret" {
  for_each           = var.additional_users
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "1.3.0"
  environment        = var.environment
  secret_name_prefix = "PYPISERVER_${each.key}_"
  secret_description = "Username and password of the ${each.key} user for basic http authentication on the PyPI server."
  secret_value = jsonencode(
    {
      username : each.key
      password : random_password.additional[each.key].result
      bcrypt_hash : random_password.additional[each.key].bcrypt_hash
    }
  )
  readers = each.value.secret_readers
}

locals {
  # One "user:bcrypt_hash" line per user. Only hashes reach the instance, never passwords.
  htpasswd_content = join(
    "\n",
    concat(
      [
        format(
          "%s:%s",
          jsondecode(module.pypiserver_secret.secret_value)["username"],
          jsondecode(module.pypiserver_secret.secret_value)["bcrypt_hash"]
        )
      ],
      [
        for username in sort(keys(var.additional_users)) :
        format("%s:%s", username, random_password.additional[username].bcrypt_hash)
      ]
    )
  )
}
