# Как установить (шаги)

Загрузись с NixOS 24.11 Live-ISO (UEFI).
Подключи сеть (в Live-ISO обычно уже есть NetworkManager).
Сохрани в /root три файла (flake.nix, configuration.nix, home.nix) — содержимое см. выше. И скрипт install.sh.
```nano /root/install.sh``` и вставь текст скрипта; аналогично создай ```/root/flake.nix```, ```/root/configuration.nix```, ```/root/home.nix```, чтобы потом вставить в скрипт (места с <ВСТАВЬ...>).

Или отредактируй скрипт, чтобы он сам скачал эти файлы из репозитория.

``` sh
  chmod +x install.sh
  ./install.sh
```
