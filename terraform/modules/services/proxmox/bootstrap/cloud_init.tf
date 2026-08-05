resource "proxmox_virtual_environment_download_file" "ubuntu" {
  node_name    = var.node_name
  content_type = "iso"
  datastore_id = proxmox_virtual_environment_storage_directory.tfdata.id
  url          = var.cloud_image_url
  file_name    = "ubuntu-24.04-cloudimg-amd64.img"
}

# Cloud-init robi absolutne minimum: użytkownik, klucze, port SSH i qemu-guest-agent.
# Wszystko ponad to należy do Ansible - inaczej zmiana konfiguracji wymagałaby
# odtworzenia VM-ki zamiast ponownego uruchomienia playbooka.
resource "proxmox_virtual_environment_file" "cloud_init" {
  node_name    = var.node_name
  content_type = "snippets"
  datastore_id = proxmox_virtual_environment_storage_directory.tfdata.id

  source_raw {
    # Nazwa STABILNA, bez skrótu treści.
    #
    # Wersja z md5 w nazwie powodowała, że zmiana szablonu tworzyła nowy plik,
    # a stary znikał - podczas gdy maszyny (przez ignore_changes) nadal wskazywały
    # na usuniętą ścieżkę. Objawiało się to dopiero przy ich restarcie:
    # "volume does not exist" i maszyna nie wstawała.
    #
    # Przy stałej nazwie plik jest podmieniany w miejscu, a maszyny zawsze
    # wskazują na coś istniejącego.
    file_name = "cloud-init-common.yml"
    data      = local.cloud_init
  }
}
