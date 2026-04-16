# Audit exhaustif — Modèle de données `missions`

> Date : 2026-04-16
> Auteur : Claude (assisté par Gabrielle Picard)
> Objectif : Documenter l'état actuel du modèle mission avant refonte multi-créneaux

---

## Table des matières

1. [Modèle actuel — Schéma de la table `missions`](#1-modèle-actuel)
2. [Cartographie des usages (frontend, edge functions, triggers, RPCs)](#2-cartographie-des-usages)
3. [Bug B — Analyse `serie_id` et missions récurrentes](#3-bug-b)
4. [Contraintes légales — Pauses et déclaration horaire en intérim santé](#4-contraintes-légales)
5. [Proposition de modèle cible — `mission_creneaux`](#5-modèle-cible)
6. [Plan de migration des 268 missions existantes](#6-plan-de-migration)
7. [Impact estimé sur le code](#7-impact-estimé)
8. [Décisions à arbitrer par Gabrielle](#8-décisions)
