-- =============================================================================
-- PROYECTO: TurnoÁgil - Sistema de Gestión de Turnos
-- MOTOR: MySQL 8.0 (InnoDB, UTF8mb4)
-- ESQUEMA: TurnoAgil
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS `TurnoAgil` 
  DEFAULT CHARACTER SET utf8mb4 
  COLLATE utf8mb4_unicode_ci;

USE `TurnoAgil`;

-- Desactivar temporalmente restricciones de FK para recreación de tablas
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `atenciones`;
DROP TABLE IF EXISTS `turnos`;
DROP TABLE IF EXISTS `usuarios`;
DROP TABLE IF EXISTS `roles`;
DROP TABLE IF EXISTS `estados_turno`;
DROP TABLE IF EXISTS `servicios`;

SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
-- 1. TABLA: roles
-- Almacena los perfiles del sistema (Administrador, Auxiliar, Usuario) (RAS-5)
-- -----------------------------------------------------------------------------
CREATE TABLE `roles` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `nombre` VARCHAR(50) NOT NULL,
  `descripcion` VARCHAR(255) NULL,
  `creado_en` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `uk_roles_nombre` (`nombre` ASC)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- 2. TABLA: usuarios
-- Registra los usuarios autenticados y operadores de ventanilla
-- -----------------------------------------------------------------------------
CREATE TABLE `usuarios` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `rol_id` INT UNSIGNED NOT NULL,
  `nombre_completo` VARCHAR(150) NOT NULL,
  `correo` VARCHAR(120) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `ventanilla` VARCHAR(20) NULL COMMENT 'Identificador de puesto o ventanilla (ej: Modulo 1)',
  `activo` TINYINT(1) NOT NULL DEFAULT 1,
  `creado_en` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `actualizado_en` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `uk_usuarios_correo` (`correo` ASC),
  INDEX `fk_usuarios_roles_idx` (`rol_id` ASC),
  CONSTRAINT `fk_usuarios_roles`
    FOREIGN KEY (`rol_id`)
    REFERENCES `roles` (`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- 3. TABLA: servicios
-- Define las áreas de atención (ej: Caja, Asesoría, Reclamaciones)
-- -----------------------------------------------------------------------------
CREATE TABLE `servicios` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `codigo` VARCHAR(10) NOT NULL COMMENT 'Prefijo para el ticket (ej: CAJ, ASES)',
  `nombre` VARCHAR(100) NOT NULL,
  `descripcion` VARCHAR(255) NULL,
  `activo` TINYINT(1) NOT NULL DEFAULT 1,
  `creado_en` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `uk_servicios_codigo` (`codigo` ASC)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- 4. TABLA: estados_turno
-- Catálogo de estados: PENDIENTE, LLAMADO, EN_ATENCION, ATENDIDO, AUSENTE, CANCELADO
-- -----------------------------------------------------------------------------
CREATE TABLE `estados_turno` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `codigo` VARCHAR(30) NOT NULL,
  `descripcion` VARCHAR(150) NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `uk_estados_codigo` (`codigo` ASC)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- 5. TABLA: turnos
-- Núcleo transaccional del Módulo de Turnos (F-01, F-02, F-03, RAS-1, RAS-3)
-- -----------------------------------------------------------------------------
CREATE TABLE `turnos` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `codigo` VARCHAR(20) NOT NULL COMMENT 'Código legible por el usuario (ej: CAJ-001)',
  `numero_secuencia` INT UNSIGNED NOT NULL COMMENT 'Consecutivo dentro de la jornada',
  `servicio_id` INT UNSIGNED NOT NULL,
  `estado_id` INT UNSIGNED NOT NULL,
  `usuario_solicitante_id` INT UNSIGNED NULL COMMENT 'Opcional si el cliente está registrado',
  `fecha_jornada` DATE NOT NULL COMMENT 'Fecha operativa para control de unicidad diaria',
  `fecha_creacion` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `version` INT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'Control de concurrencia optimista (RowVersion)',
  PRIMARY KEY (`id`),
  -- Garantiza secuencia única por servicio cada día (RAS-1)
  UNIQUE INDEX `uk_turnos_servicio_jornada_secuencia` (`servicio_id` ASC, `fecha_jornada` ASC, `numero_secuencia` ASC),
  -- Optimización de consultas frecuentes: fila de espera y polling (RAS-2, 5.5)
  INDEX `idx_turnos_estado_fecha` (`estado_id` ASC, `fecha_creacion` ASC),
  INDEX `idx_turnos_jornada_servicio` (`fecha_jornada` ASC, `servicio_id` ASC),
  INDEX `fk_turnos_servicios_idx` (`servicio_id` ASC),
  INDEX `fk_turnos_estados_idx` (`estado_id` ASC),
  INDEX `fk_turnos_usuarios_idx` (`usuario_solicitante_id` ASC),
  CONSTRAINT `fk_turnos_servicios`
    FOREIGN KEY (`servicio_id`)
    REFERENCES `servicios` (`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,
  CONSTRAINT `fk_turnos_estados`
    FOREIGN KEY (`estado_id`)
    REFERENCES `estados_turno` (`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,
  CONSTRAINT `fk_turnos_usuarios`
    FOREIGN KEY (`usuario_solicitante_id`)
    REFERENCES `usuarios` (`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- 6. TABLA: atenciones
-- Núcleo transaccional del Módulo de Atención y Reportes (F-04, F-05, F-06, RAS-4)
-- -----------------------------------------------------------------------------
CREATE TABLE `atenciones` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `turno_id` BIGINT UNSIGNED NOT NULL,
  `auxiliar_id` INT UNSIGNED NOT NULL COMMENT 'Operador que atiende el turno',
  `ventanilla` VARCHAR(20) NOT NULL,
  `fecha_llamado` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `fecha_inicio` TIMESTAMP NULL DEFAULT NULL,
  `fecha_fin` TIMESTAMP NULL DEFAULT NULL,
  `resultado` ENUM('ATENDIDO', 'AUSENTE', 'CANCELADO') NULL DEFAULT NULL,
  `observaciones` TEXT NULL,
  `creado_en` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  -- Un turno no puede vincularse a múltiples atenciones simultáneas (RAS-3)
  UNIQUE INDEX `uk_atenciones_turno_id` (`turno_id` ASC),
  INDEX `idx_atenciones_fechas` (`fecha_llamado` ASC, `fecha_fin` ASC),
  INDEX `fk_atenciones_usuarios_idx` (`auxiliar_id` ASC),
  CONSTRAINT `fk_atenciones_turnos`
    FOREIGN KEY (`turno_id`)
    REFERENCES `turnos` (`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,
  CONSTRAINT `fk_atenciones_usuarios`
    FOREIGN KEY (`auxiliar_id`)
    REFERENCES `usuarios` (`id`)
    ON DELETE RESTRICT
    ON UPDATE CASCADE
) ENGINE = InnoDB;

USE `TurnoAgil`;

-- Inserción de Roles
INSERT INTO `roles` (`id`, `nombre`, `descripcion`) VALUES
(1, 'Administrador', 'Supervisa la operación, métricas y reportes históricos'),
(2, 'Auxiliar', 'Administra la fila, llama turnos y registra la atención'),
(3, 'Usuario', 'Solicitante presencial o web de turnos');

-- Inserción de Estados de Turno
INSERT INTO `estados_turno` (`id`, `codigo`, `descripcion`) VALUES
(1, 'PENDIENTE', 'Turno creado y esperando ser llamado en fila'),
(2, 'LLAMADO', 'Turno notificado en pantallas, esperando que el usuario se acerque'),
(3, 'EN_ATENCION', 'Atención en curso en ventanilla'),
(4, 'ATENDIDO', 'Atención finalizada con éxito'),
(5, 'AUSENTE', 'Usuario no se presentó al llamado'),
(6, 'CANCELADO', 'Turno cancelado por el usuario o personal');

-- Inserción de Servicios Iniciales
INSERT INTO `servicios` (`id`, `codigo`, `nombre`, `descripcion`) VALUES
(1, 'CAJ', 'Caja y Pagos', 'Consignaciones, retiros y pagos en ventanilla'),
(2, 'ASE', 'Asesoría Comercial', 'Apertura de productos e información general'),
(3, 'REC', 'Reclamaciones', 'Gestión de quejas, reclamos y servicio al cliente');

-- Inserción de Usuario Administrador y Auxiliares de prueba
-- Contraseña de prueba: PasswordHashDemo123 (requiere bcrypt/argon2 desde la API)
INSERT INTO `usuarios` (`id`, `rol_id`, `nombre_completo`, `correo`, `password_hash`, `ventanilla`) VALUES
(1, 1, 'Administrador Sistema', 'admin@turnoagil.local', '$2a$11$DummyHashAdminSecureTurnoAgil2026', NULL),
(2, 2, 'Auxiliar Ventanilla 1', 'caja1@turnoagil.local', '$2a$11$DummyHashAuxiliar1Secure2026', 'Módulo 1'),
(3, 2, 'Auxiliar Ventanilla 2', 'asesor1@turnoagil.local', '$2a$11$DummyHashAuxiliar2Secure2026', 'Módulo 2');

USE `TurnoAgil`;

-- Vista para consultar la fila en vivo (F-03 y Polling cada 5s)
CREATE OR REPLACE VIEW `vw_fila_pendiente` AS
SELECT 
    t.id AS turno_id,
    t.codigo,
    s.nombre AS servicio,
    e.codigo AS estado,
    t.fecha_creacion,
    TIMESTAMPDIFF(MINUTE, t.fecha_creacion, NOW()) AS minutos_espera
FROM `turnos` t
INNER JOIN `servicios` s ON t.servicio_id = s.id
INNER JOIN `estados_turno` e ON t.estado_id = e.id
WHERE e.codigo IN ('PENDIENTE', 'LLAMADO')
ORDER BY t.fecha_creacion ASC;

-- Vista para consolidar indicadores históricos y tiempos de atención (F-07)
CREATE OR REPLACE VIEW `vw_reporte_tiempos_atencion` AS
SELECT 
    t.id AS turno_id,
    t.codigo AS codigo_turno,
    t.fecha_jornada,
    s.nombre AS servicio,
    u.nombre_completo AS auxiliar,
    a.ventanilla,
    e.codigo AS estado_final,
    t.fecha_creacion,
    a.fecha_llamado,
    a.fecha_inicio,
    a.fecha_fin,
    -- Tiempo que esperó el cliente desde que sacó el ticket hasta que fue llamado (segundos)
    TIMESTAMPDIFF(SECOND, t.fecha_creacion, a.fecha_llamado) AS segundos_espera,
    -- Tiempo real de servicio prestado en el módulo (segundos)
    TIMESTAMPDIFF(SECOND, a.fecha_inicio, a.fecha_fin) AS segundos_atencion
FROM `turnos` t
INNER JOIN `servicios` s ON t.servicio_id = s.id
INNER JOIN `estados_turno` e ON t.estado_id = e.id
LEFT JOIN `atenciones` a ON t.id = a.turno_id
LEFT JOIN `usuarios` u ON a.auxiliar_id = u.id;