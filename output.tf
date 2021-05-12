#output "pool_public_ip" {
  #value = "${google_compute_forwarding_rule.default.ip_address}"
#}
# google_compute_instance.db.network_interface.access_config.nat_ip

output "instance_db_ips" {
  value = "${join(" ", google_compute_instance.db.*.network_interface.0.network_ip)}"
}

#output "public_ip" {
  #value = "${google_compute_address.db[0].address}"
#}

output "instance_external_ips" {
  value = "${join(" ", google_compute_instance.db.*.network_interface.0.access_config.0.nat_ip)}"
}

