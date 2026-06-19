# Hosted zone for devbox.farm. After apply, delegate the domain at the registrar
# by pointing its NS records at the route53_name_servers output.
resource "aws_route53_zone" "devbox_farm" {
  name = "devbox.farm"

  tags = local.tags
}
