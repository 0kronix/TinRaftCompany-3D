extends RefCounted
class_name SyncConventions
## Краткая «карта» каналов репликации в проекте — ориентир для новых сущностей.
##
## NetworkManager остаётся автозагрузкой с `@rpc`; логику команд, airlock, шаттла и статического деспавна —
## в `network/core/services/` и `StaticDespawnTracker`.
## Общая проверка сессии (`OfflineMultiplayerPeer` и т.д.) — `MultiplayerRuntime`; поза RB с сервера —
## `WorldRigidReplicaSync`; текущий «локальный» игрок по группе/`Player_*` — `LocalPlayerFinder`.

##
## SERVER_PHYSICS_RIGIDBODY: authority = 1, клиенты freeze kinematic,
## поза по `NetworkManager.broadcast_world_rigid_transform` или `NetworkReplicatedRigidBody`.
##
## SPAWNER_DYNAMIC: `MultiplayerSpawner.spawn_function`, начальное состояние в Dictionary при spawn.
##
## CLIENT_OWNED_CHARACTER: `MultiplayerSynchronizer` + SceneReplicationConfig (игрок).
##
## STATIC_DESPAWN: сервер `NetworkManager.notify_node_despawned` до queue_free;
## поздний join — `world_manager._rpc_sync_destroyed` после `_rpc_client_ready`.
##
## FIELD_ASTEROIDS: `NetworkManager.broadcast_field_asteroid_spawn` / batch late join.
