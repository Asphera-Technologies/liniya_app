# Документация Linea

Порядок чтения для того, кто поднимает контекст с нуля:

1. [brief.md](brief.md) — исходный бриф заказчика (как есть).
2. [product.md](product.md) — что строим, юзкейсы v1, критерий успеха.
3. [how-to-run.md](how-to-run.md) — как запустить приложение на iPhone и что
   смотреть. Для того, кто будет проверять результат.
4. [testing-round-1.md](testing-round-1.md) — что проверить в правках от
   16 сентября: по каждой фиче, как должно работать и куда смотреть.
5. [secrets.md](secrets.md) — где хранить ключ доступа к модели и почему
   ключ внутри приложения не секрет.
6. [architecture.md](architecture.md) — текущая архитектура приложения и слои.
7. [intelligence.md](intelligence.md) — спецификация Intelligence-ядра:
   модель данных, протоколы, формулы State/Decision/Feedback Engine,
   объяснения, рецепт коннектора, тесты.
8. [vkusvill.md](vkusvill.md) — интеграция с каталогом ВкусВилла: что
   получилось, чего в их API нет и почему.
9. [connectors.md](connectors.md) — как подключить новый источник данных
   (календарь, питание, локация) не трогая ядро.
10. [decisions.md](decisions.md) — журнал архитектурных решений (ADR) с
   обоснованиями.
11. [open-questions.md](open-questions.md) — вопросы заказчику и дефолты, по
   которым идёт работа.
12. [roadmap.md](roadmap.md) — этапы, статусы, чек-лист проверки на Mac,
   журнал работ.
13. [glossary.md](glossary.md) — термины и соответствующие типы.
14. [development.md](development.md) — процесс команды (ветки, PR).

Как запустить тесты ядра без Xcode: `Scripts/test-core.sh` (нужен Docker).
Линтер границ ядра: `Scripts/check-layers.sh`.
