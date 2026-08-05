# Osobny root ze stanem LOKALNYM - i to nie jest niedopatrzenie.
#
# Ten katalog tworzy bucket, w którym mieszka stan całej reszty infrastruktury.
# Nie może więc sam trzymać stanu w buckecie, który dopiero powstanie.
# Klasyczny problem kury i jajka; rozwiązanie: uruchamiany raz, stan lokalny.
#
# Plik terraform.tfstate z tego katalogu jest w .gitignore - zawiera klucze IAM.
terraform {
  required_version = "1.14.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.31.0"
    }
  }
}
