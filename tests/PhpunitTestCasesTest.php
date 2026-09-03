<?php

declare(strict_types=1);

namespace App\Tests;

use Ubix\Tests\AbstractPhpunitTestCasesTestCase as PhpunitTestCasesTestCase;

/**
 * PHPUnit test case proving every concrete class and enum under php/App has a test case
 */
final class PhpunitTestCasesTest extends PhpunitTestCasesTestCase
{
    /**
     * Test that all concrete classes and enums have a corresponding PHPUnit test case
     *
     * @return void
     */
    public function testEveryConcreteClassAndEnumHasAPhpunitTestCase(): void
    {
        $this->assertEveryConcreteClassAndEnumHasATestCase();
    }

    /**
     * {@inheritDoc}
     */
    protected function getCodeDirectory(): string
    {
        return dirname(__DIR__) . '/php/App';
    }

    /**
     * {@inheritDoc}
     */
    protected function getCodeNamespace(): string
    {
        return 'App';
    }

    /**
     * {@inheritDoc}
     */
    protected function getTestsDirectory(): string
    {
        return __DIR__;
    }

    /**
     * {@inheritDoc}
     */
    protected function getTestsNamespace(): string
    {
        return 'App\\Tests';
    }
}
