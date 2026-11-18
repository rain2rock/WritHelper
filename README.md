# WritHelper Forever

[English](#english) · [Русский](#русский)

## English

WritHelper Forever helps you find the cheapest Craftsman’s Writs to complete in World of Warcraft: Forever. These daily quests earn reputation with your side’s trade faction:

- **Alliance** — Azeroth Commerce Authority
- **Horde** — Durotar Supply and Logistics

Scan the Auction House to compare the cost of buying a writ and its required items. If your character knows the recipe, you can compare buying the finished item with crafting it from materials you own or need to buy.

### Installation

Copy the `WritHelper` folder into `World of Warcraft/_forever_/Interface/AddOns/`. Restart the game or run `/reload`, then enable WritHelper in the AddOns list. Open it with `/writ`, the minimap button, or the Auction House button.

The interface is available in English, Russian, and Simplified Chinese. It uses the game language by default. You can change it in Settings. Item and recipe names come from the game client.

### How to use

1. Open your profession window so the add-on can record known recipes. Open your bank to record the materials stored there.
2. Open the Auction House and click **Scan auction house**. If a full scan is unavailable, WritHelper can fall back to a standard search.
3. Filter by profession, reputation reward, or turn-in location. You can hide writs completed today, sort by total cost or cost per reputation point, and open a shopping list for the selected writ.

WritHelper can use cached prices from Auctionator, TradeSkillMaster, and Auctioneer when available. Cached prices and market estimates cannot confirm current availability. Scan results can also go out of date. Crafting estimates treat materials you already own as having zero purchase cost. Buying materials may require buying whole stacks.

Completed writs are based on what the game reports since the daily reset. Quest coverage and completion checks depend on the data available to the client and may be incomplete. WritHelper does not make purchases.

### Data

The database contains 150 writ-to-item mappings. It draws on [WoW Forever Market Tools](https://github.com/AidVir/wow-forever-favor), with some entries checked against [Icy Veins](https://db.icy-veins.com/wow-forever/). Some entries remain unverified, and sources disagree on faction assignments for individual writs.

`tools/update_writs.py` is a helper script for checking the database. Automatic scheduling and the game installation path are configured separately. For a different installation, pass the add-on path with `--addon`.

### License

Only free personal, non-commercial use of the unmodified add-on is permitted. See [LICENSE](LICENSE) for the terms.

## Русский

WritHelper Forever помогает выбрать самые выгодные заказы мастера в World of Warcraft: Forever. Эти ежедневные задания дают репутацию с торговой фракцией вашей стороны:

- **Альянс** — Azeroth Commerce Authority
- **Орда** — Durotar Supply and Logistics

Аддон сравнивает стоимость покупки заказа и готовых предметов со стоимостью самостоятельного изготовления, если персонаж знает рецепт.

### Установка

Скопируйте папку `WritHelper` в `World of Warcraft/_forever_/Interface/AddOns/`, перезапустите игру или введите `/reload` и включите аддон в списке модификаций. Открыть окно можно командой `/writ`, кнопкой у миникарты или кнопкой на аукционе.

Интерфейс доступен на русском, английском и упрощённом китайском. По умолчанию используется язык клиента, а в настройках можно выбрать язык вручную. Названия предметов и рецептов предоставляет игра.

### Как пользоваться

1. Откройте окно профессии, чтобы аддон записал известные персонажу рецепты. Откройте банк, чтобы сохранить сведения о материалах в нём.
2. Откройте аукцион и нажмите «Сканировать аукцион». При недоступности полного запроса аддон может перейти к обычному поиску.
3. Сравните заказы в списке. Фильтруйте заказы по профессии, награде в репутации и месту сдачи, скрывайте выполненные заказы и сортируйте по общей стоимости или цене за очко репутации. Для выбранного заказа можно открыть список покупок.

Аддон может использовать сохранённые цены Auctionator, TradeSkillMaster и Auctioneer, если они установлены и предоставляют данные. Внешние цены и рыночные оценки не подтверждают наличие товара. Собственные данные сканирования также могут устареть. При сравнении изготовления уже имеющиеся материалы считаются бесплатными, а закупка может включать целые стопки.

Аддон отмечает задания, которые игра считает сданными после дневного сброса. Проверка и охват базы заданий зависят от данных клиента и могут быть неполными. Покупки аддон не совершает.

### Данные

В базе содержится 150 сопоставлений заказов и предметов. Источники: [WoW Forever Market Tools](https://github.com/AidVir/wow-forever-favor) и проверка отдельных данных по [Icy Veins](https://db.icy-veins.com/wow-forever/). Не все записи независимо подтверждены. Сведения о принадлежности отдельных заказов к фракциям расходятся между источниками.

`tools/update_writs.py` — вспомогательный скрипт для проверки базы. Автозапуск и путь к установленной игре настраиваются отдельно; текущий путь по умолчанию привязан к исходной установке и для другой системы его нужно передать через `--addon`.

### Лицензия

Разрешено только бесплатное личное некоммерческое использование аддона в неизменённом виде. Условия указаны в файле [LICENSE](LICENSE).
