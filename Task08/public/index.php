<?php

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$pageTitle = 'Станция технического обслуживания';
require __DIR__ . '/../templates/header.php';
?>
    <p>Выберите форму для ввода данных:</p>

    <ul class="cards">
        <li>
            <a href="master_form.php">Добавить мастера</a>
            <p>Кадровые данные мастера, процент от выручки и услуги, которые он может выполнять.</p>
        </li>
        <li>
            <a href="schedule_form.php">График работы мастеров</a>
            <p>Рабочие смены мастеров по дням.</p>
        </li>
        <li>
            <a href="appointment_form.php">Предварительная запись</a>
            <p>Выбор услуги, мастера и свободного времени.</p>
        </li>
    </ul>
<?php require __DIR__ . '/../templates/footer.php'; ?>
