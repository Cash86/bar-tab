from collections.abc import Iterator
from contextlib import contextmanager

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from bartab.api.deps import get_clock, get_session, require_admin
from bartab.api.schemas import (
    DrinkCreate,
    DrinkOut,
    DrinkUpdate,
    ErrorResponse,
    GroupOut,
    GroupWrite,
    OrderWrite,
    PersonCreate,
    PersonOut,
    PersonUpdate,
    PriceTierOut,
    TierWrite,
)
from bartab.domain.clock import Clock
from bartab.domain.names import InvalidName
from bartab.persistence import master_data
from bartab.persistence.models import Drink, DrinkGroup, DrinkPrice, Person, PriceTier

router = APIRouter()

ERRORS = {
    401: {"model": ErrorResponse},
    404: {"model": ErrorResponse},
    409: {"model": ErrorResponse},
    422: {"model": ErrorResponse},
}


@contextmanager
def _mapped_errors() -> Iterator[None]:
    try:
        yield
    except master_data.NotFound:
        raise HTTPException(status_code=404, detail="not_found") from None
    except master_data.Conflict as error:
        raise HTTPException(status_code=409, detail=error.detail) from None
    except master_data.Invalid as error:
        raise HTTPException(status_code=422, detail=error.detail) from None
    except InvalidName:
        raise HTTPException(status_code=422, detail="invalid_name") from None


def _person(row: Person) -> PersonOut:
    return PersonOut(
        id=row.id,
        name=row.name,
        price_tier_id=row.price_tier_id,
        is_hidden=row.is_hidden,
        is_collective=row.is_collective,
        is_active=row.is_active,
    )


def _drink(session: Session, row: Drink) -> DrinkOut:
    prices = session.execute(
        select(DrinkPrice.price_tier_id, DrinkPrice.price_cents).where(
            DrinkPrice.drink_id == row.id
        )
    )
    return DrinkOut(
        id=row.id,
        name=row.name,
        group_id=row.group_id,
        crate_size=row.crate_size,
        sort_order=row.sort_order,
        is_hidden=row.is_hidden,
        is_active=row.is_active,
        prices={tier_id: cents for tier_id, cents in prices},
    )


def _group(row: DrinkGroup) -> GroupOut:
    return GroupOut(id=row.id, name=row.name, sort_order=row.sort_order, color=row.color)


def _tier(row: PriceTier) -> PriceTierOut:
    return PriceTierOut(id=row.id, name=row.name, sort_order=row.sort_order)


@router.post(
    "/admin/persons",
    name="createPerson",
    status_code=201,
    response_model=PersonOut,
    responses=ERRORS,
)
def create_person(
    body: PersonCreate,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> PersonOut:
    with _mapped_errors():
        return _person(master_data.create_person(session, clock, **body.model_dump()))


@router.put(
    "/admin/persons/{person_id}",
    name="updatePerson",
    response_model=PersonOut,
    responses=ERRORS,
)
def update_person(
    person_id: str,
    body: PersonUpdate,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> PersonOut:
    with _mapped_errors():
        return _person(master_data.update_person(session, clock, person_id, **body.model_dump()))


@router.post(
    "/admin/drinks",
    name="createDrink",
    status_code=201,
    response_model=DrinkOut,
    responses=ERRORS,
)
def create_drink(
    body: DrinkCreate,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> DrinkOut:
    with _mapped_errors():
        return _drink(session, master_data.create_drink(session, clock, **body.model_dump()))


@router.put(
    "/admin/drinks/{drink_id}",
    name="updateDrink",
    response_model=DrinkOut,
    responses=ERRORS,
)
def update_drink(
    drink_id: str,
    body: DrinkUpdate,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> DrinkOut:
    with _mapped_errors():
        drink = master_data.update_drink(session, clock, drink_id, **body.model_dump())
        return _drink(session, drink)


@router.post(
    "/admin/groups",
    name="createGroup",
    status_code=201,
    response_model=GroupOut,
    responses=ERRORS,
)
def create_group(
    body: GroupWrite,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> GroupOut:
    with _mapped_errors():
        return _group(master_data.create_group(session, clock, **body.model_dump()))


@router.put(
    "/admin/groups/{group_id}",
    name="updateGroup",
    response_model=GroupOut,
    responses=ERRORS,
)
def update_group(
    group_id: str,
    body: GroupWrite,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> GroupOut:
    with _mapped_errors():
        return _group(master_data.update_group(session, clock, group_id, **body.model_dump()))


@router.delete(
    "/admin/groups/{group_id}",
    name="deleteGroup",
    status_code=204,
    responses=ERRORS,
)
def delete_group(
    group_id: str,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
) -> Response:
    with _mapped_errors():
        master_data.delete_group(session, group_id)
    return Response(status_code=204)


@router.post(
    "/admin/price-tiers",
    name="createPriceTier",
    status_code=201,
    response_model=PriceTierOut,
    responses=ERRORS,
)
def create_price_tier(
    body: TierWrite,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> PriceTierOut:
    with _mapped_errors():
        return _tier(master_data.create_tier(session, clock, **body.model_dump()))


@router.put(
    "/admin/price-tiers/{tier_id}",
    name="updatePriceTier",
    response_model=PriceTierOut,
    responses=ERRORS,
)
def update_price_tier(
    tier_id: str,
    body: TierWrite,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> PriceTierOut:
    with _mapped_errors():
        return _tier(master_data.update_tier(session, clock, tier_id, **body.model_dump()))


@router.delete(
    "/admin/price-tiers/{tier_id}",
    name="deletePriceTier",
    status_code=204,
    responses=ERRORS,
)
def delete_price_tier(
    tier_id: str,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
) -> Response:
    with _mapped_errors():
        master_data.delete_tier(session, tier_id)
    return Response(status_code=204)


@router.put(
    "/admin/order/groups",
    name="reorderGroups",
    status_code=204,
    responses=ERRORS,
)
def reorder_groups(
    body: OrderWrite,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> Response:
    with _mapped_errors():
        master_data.reorder_groups(session, clock, body.ids)
    return Response(status_code=204)


@router.put(
    "/admin/order/price-tiers",
    name="reorderPriceTiers",
    status_code=204,
    responses=ERRORS,
)
def reorder_price_tiers(
    body: OrderWrite,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> Response:
    with _mapped_errors():
        master_data.reorder_tiers(session, clock, body.ids)
    return Response(status_code=204)


@router.put(
    "/admin/order/drinks/{group_id}",
    name="reorderDrinks",
    status_code=204,
    responses=ERRORS,
)
def reorder_drinks(
    group_id: str,
    body: OrderWrite,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> Response:
    with _mapped_errors():
        if session.get(DrinkGroup, group_id) is None:
            raise master_data.NotFound(group_id)
        master_data.reorder_drinks(session, clock, group_id, body.ids)
    return Response(status_code=204)
