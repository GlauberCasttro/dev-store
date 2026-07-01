---
description: "Regras e critérios idiomáticos para a fronteira dev-customers"
globs: ["src/services/DevStore.Customers.API/**"]
---

# Layer Rule — dev-customers (bounded context Customers)

Destino sancionado dos how-tos e critérios idiomáticos do bounded context Customers
(Customer/Address/SocialNumber, CQRS via MediatR, criação reativa a evento). O cartão do
agente (`.claude/agents/dev-customers.md`) cobre persona/escopo/território — este arquivo
cobre COMO fazer e O QUE é objetivamente checável nesta fronteira.

## How-tos da camada

### 1. Nunca criar Customer via HTTP direto — sempre via evento

A criação de `Customer` é 100% reativa a `UserRegisteredIntegrationEvent`. Um novo fluxo de
cadastro nunca adiciona `POST /customers` — estende o consumer existente:

```csharp
// Services/NewCustomerIntegrationHandler.cs
public async Task Consume(ConsumeContext<UserRegisteredIntegrationEvent> context)
{
    var msg = context.Message;

    if (await _customerRepository.CheckBySocialNumber(msg.SocialNumber))
    {
        await context.RespondAsync(new ResponseMessage(false, "SocialNumber já cadastrado"));
        return;
    }

    var command = new NewCustomerCommand(msg.Id, msg.Name, msg.Email, msg.SocialNumber);
    var result = await _mediatorHandler.SendCommand(command); // entra no CQRS normalmente
    await context.RespondAsync(new ResponseMessage(result.IsValid, result.Errors));
}
```

```csharp
// Controllers/CustomerController.cs — nunca adicionar isto:
// [HttpPost] public IActionResult CreateCustomer(NewCustomerViewModel vm) { ... }  ❌
```

### 2. Validação FluentValidation aninhada dentro do próprio Command

Todo `Command` novo replica o padrão de validator aninhado — nunca um `AbstractValidator<T>`
solto em outro arquivo:

```csharp
// Application/Commands/NewCustomerCommand.cs
public class NewCustomerCommand : Command
{
    public string SocialNumber { get; private set; }
    public string Email { get; private set; }

    public override bool IsValid()
    {
        ValidationResult = new NewCustomerCommandValidation().Validate(this);
        return ValidationResult.IsValid;
    }

    public class NewCustomerCommandValidation : AbstractValidator<NewCustomerCommand>
    {
        public NewCustomerCommandValidation()
        {
            RuleFor(c => c.SocialNumber).NotEmpty().Length(11);
            RuleFor(c => c.Email).NotEmpty().EmailAddress();
        }
    }
}
```

### 3. Novo campo em `Address` sem promovê-lo a aggregate root

`Address` é sempre `Entity` filha de `Customer` (FK `CustomerId`), nunca `IAggregateRoot`
próprio:

```csharp
// Models/Address.cs
public class Address : Entity   // nunca: Entity, IAggregateRoot
{
    public Guid CustomerId { get; private set; }
    public string Complement { get; private set; } // novo campo, mesmo padrão
}
```

```csharp
// Data/Mappings/AddressMapping.cs
builder.HasKey(a => a.Id);
builder.HasOne<Customer>().WithMany().HasForeignKey(a => a.CustomerId); // relação 1:N mantida
```

### 4. Handler de Command chamando `IsValid()` antes de qualquer efeito

Sem `IPipelineBehavior` de validação no repo (NET9-STACK-010) — todo Handler novo chama
`message.IsValid()` manualmente no início, nunca confiar em validação implícita:

```csharp
// Application/Commands/CustomerCommandHandler.cs
public async Task<ValidationResult> Handle(AddAddressCommand message, CancellationToken ct)
{
    if (!message.IsValid()) return message.ValidationResult;   // obrigatório, primeira linha
    // ... lógica de negócio
}
```

## Critérios idiomáticos

- [DOMAIN-CUSTOMERS-001]: não existe `[HttpPost]` de criação direta de `Customer` em `Controllers/CustomerController.cs` — checável via `grep -rn 'HttpPost' src/services/DevStore.Customers.API/Controllers`, que só deve retornar `POST customers/address`, nunca `POST customers`. Toda criação passa por `src/services/DevStore.Customers.API/Services/NewCustomerIntegrationHandler.cs:11,21,28-52`.
- [DOMAIN-CUSTOMERS-004]: `Address` implementa apenas `Entity`, nunca `IAggregateRoot`, com FK `CustomerId` — ver `src/services/DevStore.Customers.API/Models/Address.cs:6` e `Models/Customer.cs:26`. Checável confirmando a assinatura `class Address : Entity` (não `: Entity, IAggregateRoot`) e a presença da FK na migration correspondente.
- [validator_nested / anchors_gold]: todo `Command` novo replica o padrão de validator `AbstractValidator<T>` aninhado dentro do próprio Command, como `src/services/DevStore.Customers.API/Application/Commands/NewCustomerCommand.cs` (âncora gold `validator_nested`) — NÃO um validator solto registrado via `InjectValidator` (removido no FluentValidation 12, NET9-STACK-012) nem em arquivo separado do Command.
- [DOMAIN-CUSTOMERS-003]: `CustomerContext` mantém `QueryTrackingBehavior.NoTracking` + `AutoDetectChangesEnabled=false` configurados no construtor — ver `src/services/DevStore.Customers.API/Data/CustomerContext.cs:22-23` (âncora gold `dbcontext_tracking`, escolhida e `OrdersContext.cs` explicitamente REJEITADA por NET9-STACK-013). Checável via `grep -n 'QueryTrackingBehavior' CustomerContext.cs` — remover essa configuração para "resolver" um bug pontual de tracking é a violação conhecida.
- [DOMAIN-CUSTOMERS-002]: `SocialNumber` e `Email` persistem em claro (`varchar`, sem hash/conversor) em `src/services/DevStore.Customers.API/Data/Mappings/CustomerMapping.cs:18-27` — qualquer PR que altere esse mapping sem passar pelo gate `security` deve ser tratado como mudança de proteção de PII não autorizada, não como refactor incidental de schema.
