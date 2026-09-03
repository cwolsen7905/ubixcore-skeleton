<?php

declare(strict_types=1);

use DI\Container;
use DI\ContainerBuilder;
use Monolog\Handler\StreamHandler;
use Monolog\Level;
use Monolog\Logger as MonologLogger;
use Monolog\Processor\UidProcessor;
use Nyholm\Psr7\Factory\Psr17Factory;
use Psr\Http\Client\ClientInterface as HttpClient;
use Psr\Http\Message\RequestFactoryInterface as RequestFactory;
use Psr\Http\Message\ResponseFactoryInterface as ResponseFactory;
use Psr\Http\Message\StreamFactoryInterface as StreamFactory;
use Psr\Log\LoggerInterface as Logger;
use Psr\SimpleCache\CacheInterface as SimpleCache;
use Slim\Psr7\Factory\ResponseFactory as SlimResponseFactory;
use Ubix\HttpClient\CurlHttpClient;
use Ubix\Repository\SchemaMigration\SchemaMigrationReaderInterface as SchemaMigrationReader;
use Ubix\Repository\SchemaMigration\SchemaMigrationSqlRepository;
use Ubix\Repository\SchemaMigration\SchemaMigrationWriterInterface as SchemaMigrationWriter;
use Ubix\Service\Migration\MigrationFileScannerService;
use Ubix\Service\ProjectRootService;
use Ubix\Service\SlackService;
use Ubix\Service\Sql\MigrationPdoSqlService;
use Ubix\Service\Sql\MysqlPdoSqlService;
use Ubix\Service\Sql\SqlServiceInterface as SqlService;
use Ubix\SimpleCache\MemcachedLegacySimpleCache;

use function DI\autowire;
use function DI\get;

return static function (): Container {
    $appName = 'NeptuneCli';

    $memcacheServers = getenv('MEMCACHE_SERVERS');
    $memcacheServers = explode(',', is_string($memcacheServers) ? $memcacheServers : '');

    //
    //  Project root: the directory holding composer.json, app/, sql/ and vendor/.
    //  uBixCore itself is a Composer package living in vendor/, so nothing in the
    //  framework may derive this from its own __DIR__ - the host binds it here
    //  once. UBIX_PROJECT_ROOT overrides it for tooling that runs from elsewhere.
    //
    $projectRoot    = getenv('UBIX_PROJECT_ROOT');
    $projectRoot    = is_string($projectRoot) && $projectRoot !== '' ? $projectRoot : dirname(__DIR__, 3);
    $migrationsPath = $projectRoot . '/sql/migrations';

    $container = new ContainerBuilder();

    $container->addDefinitions([
        HttpClient::class                   => autowire(CurlHttpClient::class),
        Logger::class                       => autowire(MonologLogger::class)->constructorParameter('name', $appName)->constructorParameter('handlers', [new StreamHandler(getenv('LOGGER_PATH') . '/' . $appName . '.log', getenv('IS_SANDBOX') === 'true' || getenv('IS_DEV') === 'true' ? Level::Debug : Level::Info)])->constructorParameter('processors', [new UidProcessor()]),
        Psr17Factory::class                 => autowire(Psr17Factory::class),
        RequestFactory::class               => get(Psr17Factory::class),
        ResponseFactory::class              => autowire(SlimResponseFactory::class),
        SimpleCache::class                  => autowire(MemcachedLegacySimpleCache::class)->constructorParameter('servers', $memcacheServers),
        StreamFactory::class                => get(Psr17Factory::class),

        //
        //  Migration engine. The migrate:* commands are auto-discovered by
        //  bin/ubix, but the services they inject need these bindings.
        //
        MigrationFileScannerService::class  => autowire(MigrationFileScannerService::class)->constructorParameter('migrationsPath', $migrationsPath),
        ProjectRootService::class           => autowire()->constructorParameter('root', $projectRoot),
        SqlService::class                   => autowire(MysqlPdoSqlService::class),
        SchemaMigrationSqlRepository::class => autowire(SchemaMigrationSqlRepository::class)->constructorParameter('sqlService', get(MigrationPdoSqlService::class)),
        SchemaMigrationReader::class        => get(SchemaMigrationSqlRepository::class),
        SchemaMigrationWriter::class        => get(SchemaMigrationSqlRepository::class),
        SlackService::class                 => autowire()->constructorParameter('apiEndpoint', (string) getenv('SLACK_API_ENDPOINT')),
    ]);

    return $container->build();
};
