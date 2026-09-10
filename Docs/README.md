# Документация Linea

Порядок чтения для того, кто поднимает контекст с нуля:

1. [brief.md](brief.md) — исходный бриф заказчика (как есть).
2. [product.md](product.md) — что строим, юзкейсы v1, критерий успеха.
3. [how-to-run.md](how-to-run.md) — как запустить приложение на iPhone и что
   смотреть. Для того, кто будет проверять результат.
4. [architecture.md](architecture.md) — текущая архитектура приложения и слои.
5. [intelligence.md](intelligence.md) — спецификация Intelligence-ядра:
   модель данных, протоколы, формулы State/Decision/Feedback Engine,
   объяснения, рецепт коннектора, тесты.
6. [connectors.md](connectors.md) — как подключить новый источник данных
   (календарь, питание, локация) не трогая ядро.
7. [decisions.md](decisions.md) — журнал архитектурных решений (ADR) с
   обоснованиями.
8. [open-questions.md](open-questions.md) — вопросы заказчику и дефолты, по
   которым идёт работа.
9. [roadmap.md](roadmap.md) — этапы, статусы, чек-лист проверки на Mac,
   журнал работ.
10. [glossary.md](glossary.md) — термины и соответствующие типы.
11. [development.md](development.md) — процесс команды (ветки, PR).

Как запустить тесты ядра без Xcode: `Scripts/test-core.sh` (нужен Docker).
Линтер границ ядра: `Scripts/check-layers.sh`.
