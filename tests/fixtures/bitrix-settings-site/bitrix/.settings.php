<?php
return [
    'connections' => [
        'value' => [
            'default' => [
                'className' => '\\Bitrix\\Main\\DB\\MysqliConnection',
                'host' => 'localhost',
                'database' => 'settings_db',
                'login' => 'settings_user',
                'password' => 'settings_pass',
                'options' => 2,
            ],
        ],
    ],
];
